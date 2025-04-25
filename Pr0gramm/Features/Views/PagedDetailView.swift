// Pr0gramm/Pr0gramm/Features/Views/PagedDetailView.swift
// --- START OF COMPLETE FILE ---

// PagedDetailView.swift

import SwiftUI
import os
import AVKit

// --- Wrapper Struct für Sheet Item (unverändert) ---
struct PreviewLinkTarget: Identifiable {
    let id: Int // Die Item-ID selbst dient als Identifikator
}

// --- PagedDetailTabViewItem (unverändert) ---
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
    @Binding var previewLinkTarget: PreviewLinkTarget?

    var body: some View {
        DetailViewContent(
            item: item,
            keyboardActionHandler: keyboardActionHandler,
            player: player,
            onWillBeginFullScreen: onWillBeginFullScreen,
            onWillEndFullScreen: onWillEndFullScreen,
            tags: tags,
            comments: comments,
            infoLoadingStatus: infoLoadingStatus,
            previewLinkTarget: $previewLinkTarget
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
    @EnvironmentObject var authService: AuthService
    private static let logger = Logger(subsystem: Bundle.main.bundleIdentifier!, category: "PagedDetailView")

    @StateObject private var keyboardActionHandler = KeyboardActionHandler()
    @State private var player: AVPlayer? = nil
    @State private var playerItemID: Int? = nil
    @State private var muteObserver: NSKeyValueObservation? = nil
    @State private var loopObserver: NSObjectProtocol? = nil

    @State private var isFullscreen = false

    @State private var loadedInfos: [Int: ItemsInfoResponse] = [:]
    @State private var infoLoadingStatus: [Int: InfoLoadingStatus] = [:]
    private let apiService = APIService()

    @State private var previewLinkTarget: PreviewLinkTarget? = nil

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
                    onWillBeginFullScreen: {
                        Self.logger.debug("Callback: willBeginFullScreen")
                        self.isFullscreen = true
                    },
                    onWillEndFullScreen: {
                         Self.logger.debug("Callback: willEndFullScreen")
                         self.isFullscreen = false
                         if self.playerItemID == currentItem.id && self.player?.timeControlStatus != .playing {
                             Self.logger.debug("Ensuring player resumes after fullscreen end.")
                             self.player?.play()
                         }
                    },
                    previewLinkTarget: $previewLinkTarget
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
            isFullscreen = false
            keyboardActionHandler.selectNextAction = self.selectNext
            keyboardActionHandler.selectPreviousAction = self.selectPrevious
            if selectedIndex >= 0 && selectedIndex < items.count {
                 Task { await setupAndPlayPlayerIfNeeded(for: items[selectedIndex]) }
                 Task { await loadInfoIfNeeded(for: items[selectedIndex]) }
            }
        }
        .onDisappear {
             Self.logger.info("PagedDetailView disappearing. isFullscreen: \(self.isFullscreen)")
             keyboardActionHandler.selectNextAction = nil
             keyboardActionHandler.selectPreviousAction = nil
             if !isFullscreen {
                 Self.logger.info("Cleaning up player because view is disappearing (not fullscreen).")
                 cleanupCurrentPlayer()
             } else {
                 Self.logger.info("Skipping player cleanup because view is entering/is in fullscreen.")
             }
        }
        .background(KeyCommandView(handler: keyboardActionHandler))
        .sheet(item: $previewLinkTarget) { targetWrapper in
             LinkedItemPreviewWrapperView(itemID: targetWrapper.id)
                 .environmentObject(settings)
                 .environmentObject(authService)
        }
    }

    // MARK: - Player Management Methoden (unverändert)
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

        player?.pause()
        player = nil
        playerItemID = nil

        Self.logger.debug("Player state cleanup finished for item \(currentItemID).")
    }


    // --- loadInfoIfNeeded (RESTRUKTURIERT) ---
     private func loadInfoIfNeeded(for item: Item) async {
        let itemId = item.id
        let currentStatus = infoLoadingStatus[itemId]

        // Guard-Bedingung: Weitermachen, WENN NICHT (.loading oder .loaded)
        guard !(currentStatus == .loading || currentStatus == .loaded) else {
            // Wenn wir hier sind, ist der Status .loading oder .loaded -> Überspringen
            Self.logger.trace("Skipping info load for item \(itemId) - already loaded or loading.")
            return // Explizites return hier stellt sicher, dass der Guard-Body endet
        }

        // Wenn wir hier sind, ist der Status nil, .idle oder .error
        // Logge, wenn wir einen Fehler-Retry machen
        if case .error = currentStatus {
            Self.logger.debug("Retrying info load for item \(itemId) after previous error.")
        }

        // Fortfahren mit dem Laden
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
     private func selectNext() { if canSelectNext { selectedIndex += 1 } }
    private var canSelectNext: Bool { selectedIndex < items.count - 1 }
    private func selectPrevious() { if canSelectPrevious { selectedIndex -= 1 } }
    private var canSelectPrevious: Bool { selectedIndex > 0 }


    // --- currentItemTitle (unverändert) ---
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


// MARK: - Wrapper View für das Sheet (unverändert)
struct LinkedItemPreviewWrapperView: View {
    let itemID: Int
    @EnvironmentObject var settings: AppSettings
    @EnvironmentObject var authService: AuthService
    @Environment(\.dismiss) var dismiss

    var body: some View {
        NavigationStack {
            LinkedItemPreviewView(itemID: itemID)
                .environmentObject(settings)
                .environmentObject(authService)
                .navigationTitle("Vorschau")
                #if os(iOS)
                .navigationBarTitleDisplayMode(.inline)
                #endif
                .toolbar {
                    ToolbarItem(placement: .confirmationAction) {
                        Button("Fertig") {
                            dismiss()
                        }
                    }
                }
        }
    }
}


// MARK: - Preview (unverändert)
#Preview("Preview") {
    let sampleItems = [
        Item(id: 1, promoted: 1001, userId: 1, down: 15, up: 150, created: Int(Date().timeIntervalSince1970) - 200, image: "img1.jpg", thumb: "t1.jpg", fullsize: "f1.jpg", preview: nil, width: 800, height: 600, audio: false, source: "http://example.com", flags: 1, user: "UserA", mark: 1, repost: nil, variants: nil),
        Item(id: 2, promoted: 1002, userId: 1, down: 2, up: 20, created: Int(Date().timeIntervalSince1970) - 100, image: "vid1.mp4", thumb: "t2.jpg", fullsize: nil, preview: nil, width: 1920, height: 1080, audio: true, source: nil, flags: 1, user: "UserA", mark: 1, repost: false, variants: nil),
        Item(id: 3, promoted: 1003, userId: 2, down: 5, up: 50, created: Int(Date().timeIntervalSince1970) - 50, image: "img2.png", thumb: "t3.png", fullsize: "f2.png", preview: nil, width: 1024, height: 768, audio: false, source: nil, flags: 1, user: "UserB", mark: 2, repost: nil, variants: nil)
    ]
    let settings = AppSettings()
    let authService = AuthService(appSettings: settings)

    return NavigationStack {
        PagedDetailView(items: sampleItems, selectedIndex: 1)
    }
    .environmentObject(settings)
    .environmentObject(authService)
}
// --- END OF COMPLETE FILE ---
