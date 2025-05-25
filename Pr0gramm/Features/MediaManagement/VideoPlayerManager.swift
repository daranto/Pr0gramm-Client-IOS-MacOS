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

    // MARK: - Private Observer Properties
    private var muteObserver: NSKeyValueObservation? = nil
    private var loopObserver: NSObjectProtocol? = nil
    private var timeObserverToken: Any? = nil
    private var playerStatusObserver: NSKeyValueObservation? = nil


    // MARK: - Private Task Properties
    private var subtitleFetchTask: Task<Void, Never>? = nil

    // MARK: - Dependencies
    private weak var settings: AppSettings?
    private var shouldAutoplayWhenReady: Bool = false
    // --- NEW: Flag, um zu wissen, ob der Player explizit durch die View gestartet werden soll ---
    private var playCommandFromViewPending: Bool = false
    // --- END NEW ---


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

    // --- NEW: Methode für Views, um Play anzufordern ---
    @MainActor
    func requestPlay(for itemID: Int) {
        guard self.playerItemID == itemID, let player = self.player else {
            VideoPlayerManager.logger.warning("[Manager] requestPlay for item \(itemID) ignored: Player not set up for this item or player is nil.")
            return
        }
        
        if player.status == .readyToPlay {
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
    // --- END NEW ---


    /// Creates a new AVPlayer for the given video item or ensures the existing one plays if it's for the same item.
    /// Cleans up any previously active player. Reads transientSessionMuteState first, then isVideoMuted.
    /// Also fetches and parses subtitles based on AppSettings.subtitleActivationMode.
    @MainActor
    func setupPlayerIfNeeded(for item: Item, isFullscreen: Bool) {
        guard let settings = self.settings else {
            VideoPlayerManager.logger.error("[Manager] Cannot setup player: AppSettings not configured.")
            return
        }

        self.subtitleCues = []
        self.currentSubtitleText = nil
        self.subtitleError = nil
        self.subtitleFetchTask?.cancel()
        self.subtitleFetchTask = nil
        self.shouldAutoplayWhenReady = false
        self.playCommandFromViewPending = false // Zurücksetzen


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
        if playerItemID == item.id, let existingPlayer = player {
            VideoPlayerManager.logger.debug("[Manager] Player already exists for video item \(item.id). Ensuring state. IsFullscreen: \(isFullscreen)")
            
            let targetMuteState = settings.transientSessionMuteState ?? settings.isVideoMuted
            if existingPlayer.isMuted != targetMuteState {
                VideoPlayerManager.logger.trace("[Manager] Applying mute state (\(targetMuteState)) to existing player for item \(item.id).")
                existingPlayer.isMuted = targetMuteState
            }

            // --- MODIFIED: Player-Start-Logik vereinfacht, View (via isActive) sollte requestPlay() rufen ---
            if !isFullscreen {
                // Wenn die View aktiv wird, wird sie requestPlay() rufen.
                // Hier nur sicherstellen, dass der Status-Observer korrekt läuft.
                // Wenn der Player schon spielt, ist alles gut.
                VideoPlayerManager.logger.trace("[Manager] Existing player for \(item.id). Play state will be managed by view's isActive via requestPlay.")
            } else { // isFullscreen
                VideoPlayerManager.logger.trace("[Manager] Player exists for \(item.id) but isFullscreen is true. System controls playback.")
            }
            // --- END MODIFICATION ---

            if subtitleError != nil && subtitleCues.isEmpty {
                VideoPlayerManager.logger.debug("[Manager] Player exists, subtitle error was present. Attempting subtitle fetch again.")
                if let subtitleInfo = item.subtitles?.first {
                     self.subtitleFetchTask = Task {
                         await fetchAndParseSubtitles(for: item, subtitlePath: subtitleInfo.path)
                     }
                }
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

        let newPlayer = AVPlayer(url: url)
        let initialMute = settings.transientSessionMuteState ?? settings.isVideoMuted
        if settings.transientSessionMuteState == nil {
            settings.transientSessionMuteState = initialMute
        }
        newPlayer.isMuted = initialMute
        VideoPlayerManager.logger.info("[Manager] Player initial mute state for item \(item.id): \(initialMute)")


        self.player = newPlayer
        self.playerItemID = item.id

        setupObservers(for: newPlayer, item: item)

        let shouldFetchSubtitles: Bool
        switch settings.subtitleActivationMode {
        case .disabled: shouldFetchSubtitles = false
        case .alwaysOn: shouldFetchSubtitles = true
        case .automatic: shouldFetchSubtitles = initialMute
        }

        if shouldFetchSubtitles, let subtitleInfo = item.subtitles?.first {
             self.subtitleFetchTask = Task {
                 await fetchAndParseSubtitles(for: item, subtitlePath: subtitleInfo.path)
             }
        } else if !shouldFetchSubtitles && settings.subtitleActivationMode == .automatic {
             VideoPlayerManager.logger.debug("[Manager] Subtitle fetch deferred (mode=automatic, initially unmuted).")
        } else if item.subtitles?.first == nil {
             VideoPlayerManager.logger.debug("[Manager] No subtitles found in item data for \(item.id).")
        }

        if !isFullscreen {
            self.shouldAutoplayWhenReady = true // Flag für den Status-Observer, wenn nicht im Fullscreen gestartet wird
            VideoPlayerManager.logger.debug("[Manager] New player for item \(item.id). ShouldAutoplayWhenReady set to true (not fullscreen).")
        } else {
             self.shouldAutoplayWhenReady = false
             VideoPlayerManager.logger.debug("[Manager] New player for item \(item.id) started in fullscreen. ShouldAutoplayWhenReady is false.")
        }
    }

    @MainActor
    private func setupObservers(for player: AVPlayer, item: Item) {
        guard let settings = self.settings else {
             VideoPlayerManager.logger.error("[Manager] Cannot setup observers: AppSettings not configured.")
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
                if strongSettings.subtitleActivationMode == .automatic && newMutedState == true {
                    if let subtitleInfo = itemCopy.subtitles?.first, strongSelf.subtitleCues.isEmpty, strongSelf.subtitleError == nil, strongSelf.subtitleFetchTask == nil {
                        VideoPlayerManager.logger.info("[Manager] Player muted in automatic mode. Triggering deferred subtitle fetch for item \(itemCopy.id).")
                        strongSelf.subtitleFetchTask = Task {
                            await strongSelf.fetchAndParseSubtitles(for: itemCopy, subtitlePath: subtitleInfo.path)
                        }
                    }
                }
            }
        }
        VideoPlayerManager.logger.debug("[Manager] Added mute KVO observer for item \(item.id).")

        self.playerStatusObserver = player.observe(\.status, options: [.new, .initial]) { [weak self, weakPlayer = player] capturedLocalPlayer, change in
            guard let strongSelf = self, capturedLocalPlayer == weakPlayer else { return }
            Task { @MainActor in
                let currentItemID = strongSelf.playerItemID ?? -1
                if capturedLocalPlayer.status == .readyToPlay {
                    VideoPlayerManager.logger.info("[Manager] Player for item \(currentItemID) is now readyToPlay.")
                    // --- MODIFIED: Prüfe shouldAutoplayWhenReady ODER playCommandFromViewPending ---
                    if strongSelf.shouldAutoplayWhenReady || strongSelf.playCommandFromViewPending {
                        if capturedLocalPlayer.timeControlStatus != .playing {
                            VideoPlayerManager.logger.info("[Manager] Player for item \(currentItemID) ready. Autoplaying (auto: \(strongSelf.shouldAutoplayWhenReady), pending: \(strongSelf.playCommandFromViewPending)).")
                            capturedLocalPlayer.play()
                        } else {
                            VideoPlayerManager.logger.trace("[Manager] Player for item \(currentItemID) ready, but already playing.")
                        }
                        strongSelf.shouldAutoplayWhenReady = false
                        strongSelf.playCommandFromViewPending = false
                    }
                    // --- END MODIFICATION ---
                } else if capturedLocalPlayer.status == .failed {
                    VideoPlayerManager.logger.error("[Manager] Player for item \(currentItemID) failed. Error: \(String(describing: capturedLocalPlayer.error))")
                    strongSelf.shouldAutoplayWhenReady = false
                    strongSelf.playCommandFromViewPending = false
                } else if capturedLocalPlayer.status == .unknown {
                    VideoPlayerManager.logger.debug("[Manager] Player for item \(currentItemID) status is unknown.")
                }
            }
        }
        VideoPlayerManager.logger.debug("[Manager] Added player status KVO observer for item \(item.id).")


        guard let playerItem = player.currentItem else {
            VideoPlayerManager.logger.error("[Manager] Player has no currentItem for item \(item.id). Cannot add loop/time observers.")
            return
        }
        self.loopObserver = NotificationCenter.default.addObserver(forName: .AVPlayerItemDidPlayToEndTime, object: playerItem, queue: nil) { [weak self, weakPlayerItem = player.currentItem, itemID = item.id] notification in
             Task { @MainActor [weak self, weakPlayerItem, itemID] in
                 guard let strongSelf = self,
                       let capturedPlayerItem = weakPlayerItem,
                       let currentPlayer = strongSelf.player,
                       (notification.object as? AVPlayerItem) == capturedPlayerItem,
                       currentPlayer.currentItem == capturedPlayerItem,
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
        self.playCommandFromViewPending = false // Zurücksetzen
        let hadObservers = muteObserver != nil || loopObserver != nil || timeObserverToken != nil || playerStatusObserver != nil
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
        if playerStatusObserver != nil {
            playerStatusObserver?.invalidate()
            playerStatusObserver = nil
            VideoPlayerManager.logger.trace("[Manager] Invalidated player status observer internally.")
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
        let kvoStatusObserver = self.playerStatusObserver
        let ncObserver = self.loopObserver
        let timeToken = self.timeObserverToken
        Task { @MainActor [weak self] in
            guard let strongSelf = self else { return }
            kvoMuteObserver?.invalidate()
            kvoStatusObserver?.invalidate()
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
