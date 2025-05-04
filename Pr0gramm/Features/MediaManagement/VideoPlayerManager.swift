// Pr0gramm/Pr0gramm/Features/MediaManagement/VideoPlayerManager.swift
// --- START OF COMPLETE FILE ---

import Foundation
import AVKit
import Combine
import os

/// Manages the lifecycle and state of the single AVPlayer instance used across the PagedDetailView.
/// This ensures proper cleanup even when the owning view's state changes rapidly.
@MainActor
class VideoPlayerManager: ObservableObject {
    nonisolated private static let logger = Logger(subsystem: Bundle.main.bundleIdentifier!, category: "VideoPlayerManager")

    // MARK: - Published Player State
    @Published private(set) var player: AVPlayer? = nil
    @Published private(set) var playerItemID: Int? = nil

    // MARK: - Private Observer Properties
    private var muteObserver: NSKeyValueObservation? = nil
    private var loopObserver: NSObjectProtocol? = nil

    // MARK: - Dependencies
    private weak var settings: AppSettings?

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

    /// Creates a new AVPlayer for the given video item or ensures the existing one plays if it's for the same item.
    /// Cleans up any previously active player. Reads transientSessionMuteState first, then isVideoMuted.
    @MainActor
    func setupPlayerIfNeeded(for item: Item, isFullscreen: Bool) {
        guard let settings = self.settings else {
            VideoPlayerManager.logger.error("[Manager] Cannot setup player: AppSettings not configured.")
            return
        }

        guard item.isVideo else {
            if player != nil {
                VideoPlayerManager.logger.debug("[Manager] New item \(item.id) is not video. Cleaning up existing player (if any).")
                cleanupPlayer()
            } else {
                VideoPlayerManager.logger.trace("[Manager] New item \(item.id) is not video. No existing player to clean up.")
            }
            return
        }

        // If player exists for the same item, ensure playback state and mute state are correct.
        if playerItemID == item.id, let existingPlayer = player {
            VideoPlayerManager.logger.debug("[Manager] Player already exists for video item \(item.id). Ensuring state.")

            // Playback State
            if !isFullscreen && existingPlayer.timeControlStatus != .playing {
                 existingPlayer.play()
                 VideoPlayerManager.logger.trace("[Manager] Started play() for existing player \(item.id) (was not playing).")
            }

            // Mute State
            let targetMuteState = settings.transientSessionMuteState ?? settings.isVideoMuted
            if existingPlayer.isMuted != targetMuteState {
                VideoPlayerManager.logger.trace("[Manager] Applying mute state (\(targetMuteState)) to existing player for item \(item.id).")
                existingPlayer.isMuted = targetMuteState
            }
            return // Nothing more to do if player already exists
        }

        // If item changed or player doesn't exist, cleanup old player first
        cleanupPlayer() // Already ensures main thread
        VideoPlayerManager.logger.debug("[Manager] Setting up NEW player for video item \(item.id)...")

        guard let url = item.imageUrl else {
            VideoPlayerManager.logger.error("[Manager] Cannot setup player for item \(item.id): Invalid URL.")
            return
        }

        let newPlayer = AVPlayer(url: url)
        // Assign to published properties AFTER configuration
        let initialMute: Bool
        if let transientMute = settings.transientSessionMuteState {
            initialMute = transientMute
            VideoPlayerManager.logger.info("[Manager] Player initial mute state for item \(item.id) set from TRANSIENT session state: \(initialMute)")
        } else {
            initialMute = settings.isVideoMuted
            settings.transientSessionMuteState = initialMute // Initialize transient state
            VideoPlayerManager.logger.info("[Manager] Player initial mute state for item \(item.id) set from PERSISTED setting: \(initialMute). Transient session state initialized.")
        }
        newPlayer.isMuted = initialMute

        // Assign player and ID *before* setting up observers that might capture them
        self.player = newPlayer
        self.playerItemID = item.id

        setupObservers(for: newPlayer, item: item)

        // Only auto-play if NOT initially entering fullscreen
        if !isFullscreen {
            newPlayer.play()
            VideoPlayerManager.logger.debug("[Manager] Player started (Autoplay) for item \(item.id)")
        } else {
             VideoPlayerManager.logger.debug("[Manager] Skipping initial play because isFullscreen is true.")
        }
    }

    /// Sets up the necessary observers. Updates transientSessionMuteState on player changes.
    @MainActor
    private func setupObservers(for player: AVPlayer, item: Item) {
        guard let settings = self.settings else {
             VideoPlayerManager.logger.error("[Manager] Cannot setup observers: AppSettings not configured.")
             return
        }

        removeObservers() // Ensures we don't double-observe

        // Mute State Observer (KVO)
        self.muteObserver = player.observe(\.isMuted, options: [.new]) { [weak settings] _, change in
            Task { @MainActor [weak settings] in
                guard let settings = settings,
                      let newMutedState = change.newValue
                else { return }
                if settings.transientSessionMuteState != newMutedState {
                     settings.transientSessionMuteState = newMutedState
                     VideoPlayerManager.logger.info("[Manager] User changed mute via player controls. New state: \(newMutedState). Transient session state updated.")
                }
            }
        }
        VideoPlayerManager.logger.debug("[Manager] Added mute KVO observer for item \(item.id).")

        // Playback End Observer (Notification Center)
        guard let playerItem = player.currentItem else {
            VideoPlayerManager.logger.error("[Manager] Player has no currentItem for item \(item.id). Cannot add loop observer.")
            return
        }

        self.loopObserver = NotificationCenter.default.addObserver(
            forName: .AVPlayerItemDidPlayToEndTime,
            object: playerItem,
            queue: nil
        ) { [weak self] notification in
             Task { @MainActor [weak self, weak playerItem] in
                 guard let strongSelf = self,
                       let playerItem = playerItem,
                       let currentPlayer = strongSelf.player,
                       (notification.object as? AVPlayerItem) == playerItem,
                       currentPlayer.currentItem == playerItem,
                       let currentItemID = strongSelf.playerItemID,
                       currentItemID == item.id
                 else { return }
                 VideoPlayerManager.logger.debug("[Manager] Video did play to end time for item \(item.id). Seeking to zero and replaying.")
                 currentPlayer.seek(to: .zero)
                 currentPlayer.play()
             }
         }
        VideoPlayerManager.logger.debug("[Manager] Added loop observer for item \(item.id).")
    }

    /// Stops playback, removes observers, and releases references to the current AVPlayer instance.
    /// Ensures cleanup happens on the main thread.
    @MainActor
    func cleanupPlayer() {
        let cleanupItemID = self.playerItemID ?? -1
        let hadPlayer = self.player != nil

        if hadPlayer || muteObserver != nil || loopObserver != nil {
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

    /// Removes observers without stopping the player. Used internally if needed.
    @MainActor
    private func removeObservers() {
        if muteObserver != nil {
             muteObserver?.invalidate()
             muteObserver = nil
             VideoPlayerManager.logger.trace("[Manager] Invalidated mute observer internally.")
        }
        if let observer = loopObserver {
            NotificationCenter.default.removeObserver(observer)
            self.loopObserver = nil
            VideoPlayerManager.logger.trace("[Manager] Removed loop observer internally.")
        }
    }

    // --- NEW: Seek Methods ---

    /// Seeks the current player forward by a defined amount.
    @MainActor
    func seekForward() {
        guard let player = player else { return }
        let currentTime = player.currentTime()
        let targetTime = CMTimeAdd(currentTime, CMTime(seconds: seekForwardSeconds, preferredTimescale: 600))
        VideoPlayerManager.logger.debug("Seeking forward to \(CMTimeGetSeconds(targetTime))s")
        player.seek(to: targetTime, toleranceBefore: .zero, toleranceAfter: .zero)
    }

    /// Seeks the current player backward by a defined amount.
    @MainActor
    func seekBackward() {
        guard let player = player else { return }
        let currentTime = player.currentTime()
        let targetTime = CMTimeSubtract(currentTime, CMTime(seconds: seekBackwardSeconds, preferredTimescale: 600))
        VideoPlayerManager.logger.debug("Seeking backward to \(CMTimeGetSeconds(targetTime))s")
        player.seek(to: targetTime, toleranceBefore: .zero, toleranceAfter: .zero)
    }
    // --- END NEW ---

    deinit {
        let kvoObserver = self.muteObserver
        let ncObserver = self.loopObserver
        Task { @MainActor in
            if kvoObserver != nil { kvoObserver?.invalidate() }
            if let ncObserver = ncObserver { NotificationCenter.default.removeObserver(ncObserver) }
        }
         VideoPlayerManager.logger.debug("VideoPlayerManager deinit.")
    }
}
// --- END OF COMPLETE FILE ---
