// PagedDetailView.swift

import SwiftUI
import os
import AVKit

// --- PagedDetailTabViewItem (Übergibt Callbacks) ---
struct PagedDetailTabViewItem: View {
    let item: Item
    @ObservedObject var keyboardActionHandler: KeyboardActionHandler
    let player: AVPlayer?
    let tags: [ItemTag]
    let comments: [ItemComment]
    let infoLoadingStatus: InfoLoadingStatus
    let loadInfoAction: (Item) async -> Void
    let preloadInfoAction: (Item) async -> Void
    let allItems: [Item]
    let currentIndex: Int
    let onWillBeginFullScreen: () -> Void
    let onWillEndFullScreen: () -> Void

    var body: some View {
        DetailViewContent(
            item: item,
            keyboardActionHandler: keyboardActionHandler,
            player: player,
            onWillBeginFullScreen: onWillBeginFullScreen, // Weitergeben
            onWillEndFullScreen: onWillEndFullScreen,   // Weitergeben
            tags: tags,
            comments: comments,
            infoLoadingStatus: infoLoadingStatus
        )
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .onAppear {
            Task { await loadInfoAction(item) }
            if currentIndex + 1 < allItems.count { Task { await preloadInfoAction(allItems[currentIndex + 1]) } }
            if currentIndex > 0 { Task { await preloadInfoAction(allItems[currentIndex - 1]) } }
        }
    }
}


struct PagedDetailView: View {
    let items: [Item]
    @State private var selectedIndex: Int
    @Environment(\.dismiss) var dismiss
    @EnvironmentObject var settings: AppSettings
    private static let logger = Logger(subsystem: Bundle.main.bundleIdentifier!, category: "PagedDetailView")

    @StateObject private var keyboardActionHandler = KeyboardActionHandler()
    @State private var player: AVPlayer? = nil
    @State private var playerItemID: Int? = nil
    @State private var muteObserver: NSKeyValueObservation? = nil
    @State private var loopObserver: NSObjectProtocol? = nil

    // --- isFullscreen State WIEDER DA ---
    @State private var isFullscreen = false

    @State private var loadedInfos: [Int: ItemsInfoResponse] = [:]
    @State private var infoLoadingStatus: [Int: InfoLoadingStatus] = [:]
    private let apiService = APIService()

    init(items: [Item], selectedIndex: Int) {
        self.items = items
        self._selectedIndex = State(initialValue: selectedIndex)
        Self.logger.info("PagedDetailView init with selectedIndex: \(selectedIndex)")
    }

    var body: some View {
        TabView(selection: $selectedIndex) {
            ForEach(items.indices, id: \.self) { index in
                let currentItem = items[index]
                let statusForItem = infoLoadingStatus[currentItem.id] ?? .idle
                let tagsForItem = loadedInfos[currentItem.id]?.tags.sorted { $0.confidence > $1.confidence } ?? []
                let commentsForItem = loadedInfos[currentItem.id]?.comments ?? []

                PagedDetailTabViewItem(
                    item: currentItem,
                    keyboardActionHandler: keyboardActionHandler,
                    player: currentItem.id == self.playerItemID ? self.player : nil,
                    tags: tagsForItem,
                    comments: commentsForItem,
                    infoLoadingStatus: statusForItem,
                    loadInfoAction: loadInfoIfNeeded,
                    preloadInfoAction: loadInfoIfNeeded,
                    allItems: items,
                    currentIndex: index,
                    // Callbacks setzen den State
                    onWillBeginFullScreen: {
                        Self.logger.debug("Callback: willBeginFullScreen")
                        self.isFullscreen = true
                    },
                    onWillEndFullScreen: {
                         Self.logger.debug("Callback: willEndFullScreen")
                         self.isFullscreen = false
                         // Wichtig: Nach Beenden des Fullscreens sicherstellen, dass der Player spielt,
                         // falls er noch für das aktuelle Item existiert.
                         if self.playerItemID == currentItem.id && self.player?.timeControlStatus != .playing {
                             Self.logger.debug("Ensuring player resumes after fullscreen end.")
                             self.player?.play()
                         }
                    }
                )
                .tag(index)
            }
        }
        .tabViewStyle(.page(indexDisplayMode: .never))
        .navigationTitle(currentItemTitle)
        #if os(iOS)
        .navigationBarTitleDisplayMode(.inline)
        #endif
        .onChange(of: selectedIndex) { oldValue, newValue in
             Self.logger.info("Selected index changed from \(oldValue) to \(newValue)")
             if oldValue >= 0 && oldValue < items.count {
                 cleanupCurrentPlayerIfNeeded(for: items[oldValue])
             }
             if newValue >= 0 && newValue < items.count {
                  Task { await setupAndPlayPlayerIfNeeded(for: items[newValue]) }
                  Task { await loadInfoIfNeeded(for: items[newValue]) }
             }
        }
        .onAppear {
            Self.logger.info("PagedDetailView appeared. Setting up keyboard actions.")
            isFullscreen = false // Beim Erscheinen ist es nie Fullscreen
            keyboardActionHandler.selectNextAction = self.selectNext
            keyboardActionHandler.selectPreviousAction = self.selectPrevious
            if selectedIndex >= 0 && selectedIndex < items.count {
                 Task { await setupAndPlayPlayerIfNeeded(for: items[selectedIndex]) }
                 Task { await loadInfoIfNeeded(for: items[selectedIndex]) }
            }
        }
        // --- .onDisappear mit isFullscreen Check ---
        .onDisappear {
             Self.logger.info("PagedDetailView disappearing. isFullscreen: \(self.isFullscreen)")
             keyboardActionHandler.selectNextAction = nil
             keyboardActionHandler.selectPreviousAction = nil
             if !isFullscreen { // Nur cleanen, wenn NICHT fullscreen
                 Self.logger.info("Cleaning up player because view is disappearing (not fullscreen).")
                 cleanupCurrentPlayer()
             } else {
                 Self.logger.info("Skipping player cleanup because view is entering/is in fullscreen.")
                 // Wichtig: Player hier NICHT pausieren, da er im Fullscreen weiterlaufen soll
             }
        }
        .background(KeyCommandView(handler: keyboardActionHandler))
    }

    // MARK: - Player Management Methoden
    // (Bleiben wie in der Version OHNE [weak self])
     private func setupAndPlayPlayerIfNeeded(for item: Item) async {
        guard item.isVideo else {
            Self.logger.debug("Item \(item.id) is not a video. Skipping player setup.")
            if playerItemID != nil { cleanupCurrentPlayer() }
            return
        }
        guard playerItemID != item.id else {
            Self.logger.debug("Player already exists for video item \(item.id). Ensuring it plays.")
            if player?.timeControlStatus != .playing {
                player?.play()
            }
            return
        }

        cleanupCurrentPlayer()
        Self.logger.debug("Setting up player for video item \(item.id)...")
        guard let url = item.imageUrl else {
            Self.logger.error("Cannot setup player for item \(item.id): Invalid URL.")
            return
        }

        let newPlayer = AVPlayer(url: url)
        self.player = newPlayer
        self.playerItemID = item.id
        newPlayer.isMuted = settings.isVideoMuted
        Self.logger.info("Player initial mute state for item \(item.id) set to: \(settings.isVideoMuted)")

        self.muteObserver = newPlayer.observe(\.isMuted, options: [.new]) { observedPlayer, change in
             guard let newMutedState = change.newValue,
                   observedPlayer == self.player,
                   self.playerItemID == item.id
             else { return }

             Task { @MainActor in
                 if self.settings.isVideoMuted != newMutedState {
                     Self.logger.info("User changed mute via player controls for item \(item.id). New state: \(newMutedState). Updating global setting.")
                     self.settings.isVideoMuted = newMutedState
                 }
             }
         }
        Self.logger.debug("Added mute KVO observer for item \(item.id).")


        guard let playerItem = newPlayer.currentItem else {
            Self.logger.error("Newly created player has no currentItem for item \(item.id). Cannot add loop observer.")
            cleanupCurrentPlayer()
            return
        }
        self.loopObserver = NotificationCenter.default.addObserver(
            forName: .AVPlayerItemDidPlayToEndTime, object: playerItem, queue: .main
        ) { notification in
             guard let currentPlayer = self.player,
                   (notification.object as? AVPlayerItem) == currentPlayer.currentItem,
                   self.playerItemID == item.id
             else { return }

             Self.logger.debug("Video did play to end time for item \(item.id). Seeking to zero.")
             currentPlayer.seek(to: .zero)
             currentPlayer.play()
         }
        Self.logger.debug("Added loop observer for item \(item.id).")

        // Nur starten, wenn wir NICHT gerade im Fullscreen sind (sollte beim initialen Setup immer der Fall sein)
        if !isFullscreen {
            newPlayer.play()
            Self.logger.debug("Player started (Autoplay) for item \(item.id)")
        } else {
             Self.logger.debug("Skipping initial play because isFullscreen is true (should not happen here ideally).")
        }
    }


    private func cleanupCurrentPlayerIfNeeded(for item: Item) {
        if playerItemID == item.id {
            Self.logger.debug("Cleaning up player for previous item \(item.id) due to index change.")
            cleanupCurrentPlayer()
        }
    }

    private func cleanupCurrentPlayer() {
        guard player != nil || muteObserver != nil || loopObserver != nil else { return }
        let currentItemID = self.playerItemID ?? -1
        Self.logger.debug("Cleaning up player state for item \(currentItemID)...")

        muteObserver?.invalidate()
        muteObserver = nil

        if let observer = loopObserver {
            NotificationCenter.default.removeObserver(observer)
            self.loopObserver = nil
        }

        player?.pause() // Immer pausieren vor dem Zerstören
        player = nil
        playerItemID = nil

        Self.logger.debug("Player state cleanup finished for item \(currentItemID).")
    }


    // --- loadInfoIfNeeded (unverändert) ---
    // ...
     private func loadInfoIfNeeded(for item: Item) async {
        let itemId = item.id
        guard infoLoadingStatus[itemId] == nil || infoLoadingStatus[itemId] == .idle else { return }
        Self.logger.debug("Starting info load for item \(itemId)...")
        await MainActor.run { infoLoadingStatus[itemId] = .loading }
        do {
            let infoResponse = try await apiService.fetchItemInfo(itemId: itemId)
            await MainActor.run {
                loadedInfos[itemId] = infoResponse
                infoLoadingStatus[itemId] = .loaded
                Self.logger.debug("Successfully loaded info for item \(itemId). Tags: \(infoResponse.tags.count), Comments: \(infoResponse.comments.count)")
            }
        } catch {
            Self.logger.error("Failed to load info for item \(itemId): \(error.localizedDescription)")
            await MainActor.run {
                infoLoadingStatus[itemId] = .error(error.localizedDescription)
            }
        }
    }


    // --- Navigation Helpers (unverändert) ---
    // ...
     private func selectNext() { if canSelectNext { selectedIndex += 1 } }
    private var canSelectNext: Bool { selectedIndex < items.count - 1 }
    private func selectPrevious() { if canSelectPrevious { selectedIndex -= 1 } }
    private var canSelectPrevious: Bool { selectedIndex > 0 }


    // --- currentItemTitle (unverändert) ---
    // ...
      private var currentItemTitle: String {
        guard selectedIndex >= 0 && selectedIndex < items.count else { return "Detail" }
        let currentItem = items[selectedIndex]
        let status = infoLoadingStatus[currentItem.id] ?? .idle
        switch status {
        case .loaded:
            let topTag = loadedInfos[currentItem.id]?.tags.max(by: { $0.confidence < $1.confidence })?.tag
            if let tag = topTag, !tag.isEmpty { return tag }
            else { return "Post \(currentItem.id)" }
        case .loading: return "Lade Infos..."
        case .error: return "Fehler"
        case .idle: return "Post \(currentItem.id)"
        }
    }


} // Ende struct PagedDetailView

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
