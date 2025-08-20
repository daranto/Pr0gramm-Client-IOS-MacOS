// Pr0gramm/Pr0gramm/Features/MediaManagement/VideoPlayerManager.swift
// --- START OF COMPLETE FILE ---

import Foundation
import AVKit
import Combine
import os

/// Manages the lifecycle and state of the single AVPlayer instance used across the PagedDetailView.
/// This ensures proper cleanup even when the owning view's state changes rapidly.
/// Also handles fetching, parsing, and displaying video subtitles based on user settings.
@MainActor
class VideoPlayerManager: ObservableObject {
    nonisolated private static let logger = Logger(subsystem: Bundle.main.bundleIdentifier!, category: "VideoPlayerManager")

    // MARK: - Published Player State
    @Published private(set) var player: AVPlayer? = nil
    @Published private(set) var playerItemID: Int? = nil

    // MARK: - Published Subtitle State
    @Published private(set) var subtitleCues: [SubtitleCue] = []
    @Published private(set) var currentSubtitleText: String? = nil
    @Published private(set) var subtitleError: String? = nil
    
    // MARK: - Published Error/Retry State
    @Published private(set) var playerError: String? = nil
    @Published private(set) var showRetryButton: Bool = false
    private var currentItem: Item?
    private var retryCount = 0
    private let maxRetries = 3

    // MARK: - Private Observer Properties
    private var muteObserver: NSKeyValueObservation? = nil
    private var loopObserver: NSObjectProtocol? = nil
    private var timeObserverToken: Any? = nil
    private var playerItemStatusObserver: NSKeyValueObservation? = nil
    private var playerItemErrorObserver: NSKeyValueObservation? = nil


    // MARK: - Private Task Properties
    private var subtitleFetchTask: Task<Void, Never>? = nil

    // MARK: - Dependencies
    private weak var settings: AppSettings?
    private var shouldAutoplayWhenReady: Bool = false
    private var playCommandFromViewPending: Bool = false


    // Seek time constants
    private let seekForwardSeconds: Double = 10.0
    private let seekBackwardSeconds: Double = 5.0

    /// Configures the manager with necessary dependencies after initialization.
    @MainActor
    func configure(settings: AppSettings) {
        guard self.settings !== settings else {
             VideoPlayerManager.logger.trace("VideoPlayerManager already configured with this AppSettings instance.")
             return
        }
        self.settings = settings
        VideoPlayerManager.logger.debug("VideoPlayerManager configured with AppSettings.")
    }

    @MainActor
    func requestPlay(for itemID: Int) {
        guard self.playerItemID == itemID, let player = self.player else {
            VideoPlayerManager.logger.warning("[Manager] requestPlay for item \(itemID) ignored: Player not set up for this item or player is nil.")
            return
        }
        
        if player.currentItem?.status == .readyToPlay {
            if player.timeControlStatus != .playing {
                VideoPlayerManager.logger.info("[Manager] requestPlay: Player for item \(itemID) is ready and not playing. Starting play.")
                player.play()
            } else {
                VideoPlayerManager.logger.trace("[Manager] requestPlay: Player for item \(itemID) is already playing.")
            }
        } else {
            VideoPlayerManager.logger.info("[Manager] requestPlay: Player for item \(itemID) not ready. Setting playCommandFromViewPending = true.")
            self.playCommandFromViewPending = true // Merken, dass Play angefordert wurde
        }
    }


    /// Creates a new AVPlayer for the given video item or ensures the existing one plays if it's for the same item.
    /// Cleans up any previously active player. Reads transientSessionMuteState first, then isVideoMuted.
    /// Also fetches and parses subtitles based on AppSettings.subtitleActivationMode.
    @MainActor
    func setupPlayerIfNeeded(for item: Item, isFullscreen: Bool, forceReload: Bool = false) {
        guard let settings = self.settings else {
            VideoPlayerManager.logger.error("[Manager] Cannot setup player: AppSettings not configured.")
            return
        }
        
        if playerItemID != item.id || forceReload {
            self.retryCount = 0
            self.playerError = nil
            self.showRetryButton = false
            self.currentItem = nil
        }

        self.subtitleCues = []
        self.currentSubtitleText = nil
        self.subtitleError = nil
        self.subtitleFetchTask?.cancel()
        self.subtitleFetchTask = nil
        self.shouldAutoplayWhenReady = false
        self.playCommandFromViewPending = false


        guard item.isVideo else {
            if player != nil {
                VideoPlayerManager.logger.debug("[Manager] New item \(item.id) is not video. Cleaning up existing player (if any).")
                cleanupPlayer()
            } else {
                VideoPlayerManager.logger.trace("[Manager] New item \(item.id) is not video. No existing player to clean up.")
            }
            return
        }

        // Wenn Player für dieses Item schon existiert
        if !forceReload && playerItemID == item.id, let existingPlayer = player {
            VideoPlayerManager.logger.debug("[Manager] Player already exists for video item \(item.id). Ensuring state. IsFullscreen: \(isFullscreen)")
            
            let targetMuteState = settings.transientSessionMuteState ?? settings.isVideoMuted
            if existingPlayer.isMuted != targetMuteState {
                VideoPlayerManager.logger.trace("[Manager] Applying mute state (\(targetMuteState)) to existing player for item \(item.id).")
                existingPlayer.isMuted = targetMuteState
            }

            if !isFullscreen {
                VideoPlayerManager.logger.trace("[Manager] Existing player for \(item.id). Play state will be managed by view's isActive via requestPlay.")
            } else { // isFullscreen
                VideoPlayerManager.logger.trace("[Manager] Player exists for \(item.id) but isFullscreen is true. System controls playback.")
            }
            
            Task {
                await updateSubtitleStateForCurrentItem()
            }
            
            return
        }

        // Setup für einen neuen Player
        cleanupPlayer()
        VideoPlayerManager.logger.debug("[Manager] Setting up NEW player for video item \(item.id)... IsFullscreen: \(isFullscreen)")

        guard let url = item.imageUrl else {
            VideoPlayerManager.logger.error("[Manager] Cannot setup player for item \(item.id): Invalid URL.")
            return
        }

        let playerItem = AVPlayerItem(url: url)
        let newPlayer = AVPlayer(playerItem: playerItem)
        let initialMute = settings.transientSessionMuteState ?? settings.isVideoMuted
        if settings.transientSessionMuteState == nil {
            settings.transientSessionMuteState = initialMute
        }
        newPlayer.isMuted = initialMute
        VideoPlayerManager.logger.info("[Manager] Player initial mute state for item \(item.id): \(initialMute)")


        self.player = newPlayer
        self.playerItemID = item.id
        self.currentItem = item

        setupObservers(for: newPlayer, item: item)

        Task {
            await updateSubtitleStateForCurrentItem()
        }

        if !isFullscreen {
            self.shouldAutoplayWhenReady = true
            VideoPlayerManager.logger.debug("[Manager] New player for item \(item.id). ShouldAutoplayWhenReady set to true (not fullscreen).")
        } else {
             self.shouldAutoplayWhenReady = false
             VideoPlayerManager.logger.debug("[Manager] New player for item \(item.id) started in fullscreen. ShouldAutoplayWhenReady is false.")
        }
    }

    @MainActor
    private func setupObservers(for player: AVPlayer, item: Item) {
        guard let settings = self.settings, let playerItem = player.currentItem else {
             VideoPlayerManager.logger.error("[Manager] Cannot setup observers: AppSettings or player.currentItem is nil.")
             return
        }

        removeObservers()

        self.muteObserver = player.observe(\.isMuted, options: [.new]) { [weak self, weak settings, itemCopy = item] _, change in
            guard let strongSelf = self, let strongSettings = settings, let newMutedState = change.newValue else { return }
            Task { @MainActor in
                 if strongSettings.transientSessionMuteState != newMutedState {
                      strongSettings.transientSessionMuteState = newMutedState
                      VideoPlayerManager.logger.info("[Manager] User changed mute via player controls. New state: \(newMutedState). Transient session state updated.")
                 }
                // Re-evaluate subtitle state whenever mute changes
                await strongSelf.updateSubtitleStateForCurrentItem()
            }
        }
        VideoPlayerManager.logger.debug("[Manager] Added mute KVO observer for item \(item.id).")

        self.playerItemStatusObserver = playerItem.observe(\.status, options: [.new, .initial]) { [weak self, weak player, weakPlayerItem = playerItem, itemForObserver = item] capturedItem, change in
            guard let strongSelf = self, let player = player, capturedItem == weakPlayerItem else { return }
            Task { @MainActor in
                switch capturedItem.status {
                case .readyToPlay:
                    VideoPlayerManager.logger.info("[Manager] PlayerItem for item \(itemForObserver.id) is now readyToPlay.")
                    if strongSelf.shouldAutoplayWhenReady || strongSelf.playCommandFromViewPending {
                        if player.timeControlStatus != .playing {
                            VideoPlayerManager.logger.info("[Manager] PlayerItem ready. Autoplaying (auto: \(strongSelf.shouldAutoplayWhenReady), pending: \(strongSelf.playCommandFromViewPending)).")
                            player.play()
                        }
                        strongSelf.shouldAutoplayWhenReady = false
                        strongSelf.playCommandFromViewPending = false
                    }
                case .failed:
                    VideoPlayerManager.logger.error("[Manager] PlayerItem for item \(itemForObserver.id) failed. Error: \(String(describing: capturedItem.error))")
                    strongSelf.shouldAutoplayWhenReady = false
                    strongSelf.playCommandFromViewPending = false
                    strongSelf.handlePlayerFailure(for: itemForObserver, error: capturedItem.error)
                case .unknown:
                    VideoPlayerManager.logger.debug("[Manager] PlayerItem for item \(itemForObserver.id) status is unknown.")
                @unknown default:
                    VideoPlayerManager.logger.warning("[Manager] PlayerItem for item \(itemForObserver.id) has an unknown future status.")
                }
            }
        }
        VideoPlayerManager.logger.debug("[Manager] Added player item status KVO observer for item \(item.id).")

        self.playerItemErrorObserver = playerItem.observe(\.error, options: [.new]) { [weak self, itemForObserver = item] itemWithError, _ in
            guard let strongSelf = self, let error = itemWithError.error else { return }
            Task { @MainActor in
                VideoPlayerManager.logger.error("[Manager] Observed an error on playerItem for item \(itemForObserver.id): \(error.localizedDescription)")
                strongSelf.handlePlayerFailure(for: itemForObserver, error: error)
            }
        }
        VideoPlayerManager.logger.debug("[Manager] Added player item error KVO observer for item \(item.id).")


        self.loopObserver = NotificationCenter.default.addObserver(forName: .AVPlayerItemDidPlayToEndTime, object: playerItem, queue: nil) { [weak self, weakPlayerItem = player.currentItem, itemID = item.id] notification in
             Task { @MainActor [weak self, weakPlayerItem, itemID] in
                 guard let strongSelf = self,
                       let capturedItem = weakPlayerItem,
                       let currentPlayer = strongSelf.player,
                       (notification.object as? AVPlayerItem) == capturedItem,
                       currentPlayer.currentItem == capturedItem,
                       let currentManagerItemID = strongSelf.playerItemID,
                       currentManagerItemID == itemID else {
                     return
                 }
                 VideoPlayerManager.logger.debug("[Manager] Video did play to end time for item \(itemID). Seeking to zero and replaying.")
                 currentPlayer.seek(to: .zero)
                 currentPlayer.play()
             }
         }
        VideoPlayerManager.logger.debug("[Manager] Added loop observer for item \(item.id).")

        let interval = CMTime(value: 1, timescale: 4)
        self.timeObserverToken = player.addPeriodicTimeObserver(forInterval: interval, queue: nil) { [weak self] time in
             Task { @MainActor [weak self] in
                 self?.updateSubtitle(for: time)
             }
        }
        VideoPlayerManager.logger.debug("[Manager] Added periodic time observer for item \(item.id).")
    }
    
    @MainActor
    private func handlePlayerFailure(for failedItem: Item, error: Error?) {
        guard self.playerItemID == failedItem.id else {
            VideoPlayerManager.logger.warning("handlePlayerFailure for item \(failedItem.id) called, but the manager is now on item \(self.playerItemID ?? -1). Aborting.")
            return
        }

        self.currentItem = failedItem
        
        if let nsError = error as? NSError, nsError.domain == AVFoundationErrorDomain {
            if nsError.code == AVError.Code.fileFormatNotRecognized.rawValue {
                VideoPlayerManager.logger.error("Player failure for item \(failedItem.id): Format not supported. No retries will be attempted.")
                self.player = nil
                self.playerError = "Videoformat wird nicht unterstützt."
                self.showRetryButton = false
                return
            }
        }

        self.retryCount += 1
        VideoPlayerManager.logger.info("Player failure for item \(failedItem.id). Retry attempt \(self.retryCount)/\(self.maxRetries).")

        if self.retryCount < self.maxRetries {
            Task {
                try? await Task.sleep(for: .seconds(Double(self.retryCount)))
                
                guard self.playerItemID == failedItem.id, !self.showRetryButton else {
                    VideoPlayerManager.logger.info("Retry for item \(failedItem.id) cancelled, user moved on or max retries were reached.")
                    return
                }
                VideoPlayerManager.logger.info("Retrying player setup for item \(failedItem.id)...")
                
                if let url = failedItem.imageUrl, let player = self.player {
                    let newItem = AVPlayerItem(url: url)
                    self.shouldAutoplayWhenReady = true // Ensure autoplay is re-enabled for the new item
                    player.replaceCurrentItem(with: newItem)
                    setupObservers(for: player, item: failedItem)
                } else {
                    setupPlayerIfNeeded(for: failedItem, isFullscreen: false, forceReload: true)
                }
            }
        } else {
            VideoPlayerManager.logger.error("Max retries (\(self.maxRetries)) reached for item \(failedItem.id). Showing error and retry button.")
            self.player = nil
            self.playerError = "Video konnte nicht geladen werden."
            self.showRetryButton = true
        }
    }

    @MainActor
    public func forceRetry() {
        guard let itemToRetry = self.currentItem else {
            VideoPlayerManager.logger.error("forceRetry called but currentItem is nil.")
            return
        }
        VideoPlayerManager.logger.info("Force retry triggered by user for item \(itemToRetry.id).")
        self.setupPlayerIfNeeded(for: itemToRetry, isFullscreen: false, forceReload: true)
    }

    @MainActor
    private func fetchAndParseSubtitles(for item: Item, subtitlePath: String) async {
         guard !Task.isCancelled else {
              VideoPlayerManager.logger.info("[Subtitles] Fetch cancelled for item \(item.id).")
              return
         }
         guard let subtitleInfo = item.subtitles?.first(where: { $0.path == subtitlePath }),
               let subtitleURL = subtitleInfo.subtitleUrl else {
             VideoPlayerManager.logger.error("[Subtitles] Could not construct subtitle URL for item \(item.id), path: \(subtitlePath)")
             self.subtitleError = "Ungültiger Untertitel-Pfad."
             return
         }

         VideoPlayerManager.logger.info("[Subtitles] Fetching subtitles for item \(item.id) from \(subtitleURL.absoluteString)")
         self.subtitleError = nil

         do {
              let (data, response) = try await URLSession.shared.data(from: subtitleURL)
              guard !Task.isCancelled else { VideoPlayerManager.logger.info("[Subtitles] Fetch task cancelled after download for item \(item.id)."); return }
              guard let httpResponse = response as? HTTPURLResponse, (200..<300).contains(httpResponse.statusCode) else {
                   let statusCode = (response as? HTTPURLResponse)?.statusCode ?? -1
                   VideoPlayerManager.logger.error("[Subtitles] Failed to fetch VTT file for item \(item.id). Status code: \(statusCode)")
                   self.subtitleError = "Fehler beim Laden der Untertitel (\(statusCode))."
                   return
              }
              guard let vttString = String(data: data, encoding: .utf8) else {
                   VideoPlayerManager.logger.error("[Subtitles] Failed to decode VTT data to UTF-8 string for item \(item.id).")
                   self.subtitleError = "Fehler beim Dekodieren der Untertitel."
                   return
              }
              let previewLength = min(vttString.count, 500)
              let vttPreview = String(vttString.prefix(previewLength))
              VideoPlayerManager.logger.debug("[Subtitles] Fetched VTT content preview (item \(item.id)):\n---\n\(vttPreview)\n---")

              let parsedCues = VTTParser.parse(vttString)
               guard !Task.isCancelled else { VideoPlayerManager.logger.info("[Subtitles] Fetch task cancelled after parsing for item \(item.id)."); return }

              self.subtitleCues = parsedCues
              self.currentSubtitleText = nil
              VideoPlayerManager.logger.info("[Subtitles] Successfully fetched and parsed \(parsedCues.count) cues for item \(item.id).")

         } catch is CancellationError { VideoPlayerManager.logger.info("[Subtitles] URLSession task cancelled during subtitle fetch for item \(item.id).") }
           catch {
               guard !Task.isCancelled else { VideoPlayerManager.logger.info("[Subtitles] Fetch task cancelled after error for item \(item.id)."); return }
              VideoPlayerManager.logger.error("[Subtitles] Error fetching subtitles for item \(item.id): \(error.localizedDescription)")
              self.subtitleError = "Fehler beim Laden: \(error.localizedDescription)"
         }
    }

    @MainActor
    private func updateSubtitle(for time: CMTime) {
         guard CMTimeGetSeconds(time).isFinite, !subtitleCues.isEmpty else {
              if self.currentSubtitleText != nil { self.currentSubtitleText = nil }
              return
         }
         let currentTime = CMTimeGetSeconds(time)
         var foundText: String? = nil
         for cue in subtitleCues {
              if currentTime >= cue.startTime && currentTime < cue.endTime {
                   foundText = cue.text
                   break
              }
         }
         if self.currentSubtitleText != foundText {
              self.currentSubtitleText = foundText
         }
    }
    
    public func cycleSubtitleMode() {
        settings?.cycleSubtitleMode()
        Task {
            await updateSubtitleStateForCurrentItem()
        }
    }

    private func updateSubtitleStateForCurrentItem() async {
        guard let item = self.currentItem, item.id == self.playerItemID, let settings = self.settings else {
            return
        }
        guard let subtitleInfo = item.subtitles?.first, !subtitleInfo.path.isEmpty else {
            VideoPlayerManager.logger.debug("[Subtitles] No subtitles available for item \(item.id).")
            self.subtitleCues = []
            self.currentSubtitleText = nil
            return
        }

        var shouldShowSubtitles = false
        switch settings.subtitleActivationMode {
        case .disabled:
            shouldShowSubtitles = false
        case .alwaysOn:
            shouldShowSubtitles = true
        }
        
        VideoPlayerManager.logger.info("[Subtitles] Updating state for item \(item.id). Mode: \(settings.subtitleActivationMode.displayName), ShouldShow: \(shouldShowSubtitles)")

        if shouldShowSubtitles {
            if subtitleCues.isEmpty && subtitleError == nil { // Fetch only if not already loaded and no error
                subtitleFetchTask?.cancel()
                subtitleFetchTask = Task {
                    await fetchAndParseSubtitles(for: item, subtitlePath: subtitleInfo.path)
                }
            }
        } else {
            // Hide subtitles
            subtitleFetchTask?.cancel()
            self.subtitleCues = []
            self.currentSubtitleText = nil
        }
    }


    @MainActor
    func cleanupPlayer() {
        let cleanupItemID = self.playerItemID ?? -1
        let hadPlayer = self.player != nil
        let hadSubtitleTask = self.subtitleFetchTask != nil
        self.subtitleFetchTask?.cancel()
        self.subtitleFetchTask = nil
        let hadSubtitles = !self.subtitleCues.isEmpty || self.currentSubtitleText != nil || self.subtitleError != nil
        self.subtitleCues = []
        self.currentSubtitleText = nil
        self.subtitleError = nil
        self.shouldAutoplayWhenReady = false
        self.playCommandFromViewPending = false
        self.playerError = nil
        self.showRetryButton = false
        self.retryCount = 0
        self.currentItem = nil
        let hadObservers = muteObserver != nil || loopObserver != nil || timeObserverToken != nil || playerItemStatusObserver != nil
        if hadPlayer || hadObservers || hadSubtitleTask || hadSubtitles {
             VideoPlayerManager.logger.debug("[Manager] Cleaning up player state for item \(cleanupItemID)...")
        } else {
             VideoPlayerManager.logger.trace("[Manager] CleanupPlayer called, but nothing to clean up.")
             return
        }
        removeObservers()
        if let playerToCleanup = self.player {
            playerToCleanup.pause()
            self.player = nil
            VideoPlayerManager.logger.debug("[Manager] Player paused and released for item \(cleanupItemID).")
        }
        self.playerItemID = nil
        VideoPlayerManager.logger.debug("[Manager] Player state cleanup finished for item \(cleanupItemID).")
    }

    @MainActor
    private func removeObservers() {
        if muteObserver != nil {
             muteObserver?.invalidate()
             muteObserver = nil
             VideoPlayerManager.logger.trace("[Manager] Invalidated mute observer internally.")
        }
        if playerItemStatusObserver != nil {
            playerItemStatusObserver?.invalidate()
            playerItemStatusObserver = nil
            VideoPlayerManager.logger.trace("[Manager] Invalidated player item status observer internally.")
        }
        if playerItemErrorObserver != nil {
            playerItemErrorObserver?.invalidate()
            playerItemErrorObserver = nil
            VideoPlayerManager.logger.trace("[Manager] Invalidated player item error observer internally.")
        }
        if let observer = loopObserver {
            NotificationCenter.default.removeObserver(observer)
            self.loopObserver = nil
            VideoPlayerManager.logger.trace("[Manager] Removed loop observer internally.")
        }
        if let token = timeObserverToken {
             player?.removeTimeObserver(token)
             self.timeObserverToken = nil
             VideoPlayerManager.logger.trace("[Manager] Removed periodic time observer internally.")
        }
    }

    @MainActor
    func seekForward() {
        guard let player = player else { return }
        let currentTime = player.currentTime()
        let targetTime = CMTimeAdd(currentTime, CMTime(seconds: seekForwardSeconds, preferredTimescale: 600))
        VideoPlayerManager.logger.debug("Seeking forward to \(CMTimeGetSeconds(targetTime))s")
        player.seek(to: targetTime, toleranceBefore: .zero, toleranceAfter: .zero)
    }
    @MainActor
    func seekBackward() {
        guard let player = player else { return }
        let currentTime = player.currentTime()
        let targetTime = CMTimeSubtract(currentTime, CMTime(seconds: seekBackwardSeconds, preferredTimescale: 600))
        VideoPlayerManager.logger.debug("Seeking backward to \(CMTimeGetSeconds(targetTime))s")
        player.seek(to: targetTime, toleranceBefore: .zero, toleranceAfter: .zero)
    }

    deinit {
        let kvoMuteObserver = self.muteObserver
        let kvoItemStatusObserver = self.playerItemStatusObserver
        let kvoItemErrorObserver = self.playerItemErrorObserver
        let ncObserver = self.loopObserver
        let timeToken = self.timeObserverToken
        Task { @MainActor [weak self] in
            guard let strongSelf = self else { return }
            kvoMuteObserver?.invalidate()
            kvoItemStatusObserver?.invalidate()
            kvoItemErrorObserver?.invalidate()
            if let ncObserver = ncObserver { NotificationCenter.default.removeObserver(ncObserver) }
            if let token = timeToken, let player = strongSelf.player {
                player.removeTimeObserver(token)
                VideoPlayerManager.logger.trace("[Manager] Removed time observer in deinit Task.")
            } else if timeToken != nil {
                 VideoPlayerManager.logger.trace("[Manager] Could not remove time observer in deinit Task (player was nil).")
            }
            VideoPlayerManager.logger.debug("[Manager] Observer cleanup attempted in deinit via Task.")
        }
         VideoPlayerManager.logger.debug("VideoPlayerManager deinit initiated.")
    }
}
// --- END OF COMPLETE FILE ---
