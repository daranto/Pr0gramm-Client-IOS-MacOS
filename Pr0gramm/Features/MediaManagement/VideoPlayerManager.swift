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

    /// Configures the manager with necessary dependencies after initialization.
    @MainActor
    func configure(settings: AppSettings) {
        guard self.settings !== settings else {
             Self.logger.trace("VideoPlayerManager already configured with this AppSettings instance.")
             return
        }
        self.settings = settings
        Self.logger.debug("VideoPlayerManager configured with AppSettings.")
    }

    /// Creates a new AVPlayer for the given video item or ensures the existing one plays if it's for the same item.
    /// Cleans up any previously active player. Reads transientSessionMuteState first, then isVideoMuted.
    @MainActor
    func setupPlayerIfNeeded(for item: Item, isFullscreen: Bool) {
        guard let settings = self.settings else {
            Self.logger.error("[Manager] Cannot setup player: AppSettings not configured.")
            return
        }

        guard item.isVideo else {
            if player != nil {
                Self.logger.debug("[Manager] New item \(item.id) is not video. Cleaning up existing player (if any).")
                cleanupPlayer()
            } else {
                Self.logger.trace("[Manager] New item \(item.id) is not video. No existing player to clean up.")
            }
            return
        }

        // If player exists for the same item, ensure playback state and mute state are correct.
        if playerItemID == item.id, let existingPlayer = player {
            Self.logger.debug("[Manager] Player already exists for video item \(item.id). Ensuring state.")

            // --- Playback State ---
            if !isFullscreen && existingPlayer.timeControlStatus != .playing {
                 existingPlayer.play()
                 Self.logger.trace("[Manager] Started play() for existing player \(item.id) (was not playing).")
            }

            // --- Mute State ---
            let targetMuteState = settings.transientSessionMuteState ?? settings.isVideoMuted
            if existingPlayer.isMuted != targetMuteState {
                Self.logger.trace("[Manager] Applying mute state (\(targetMuteState)) to existing player for item \(item.id).")
                existingPlayer.isMuted = targetMuteState
            }
            return // Nothing more to do if player already exists
        }

        // If item changed or player doesn't exist, cleanup old player first
        cleanupPlayer() // Already ensures main thread
        Self.logger.debug("[Manager] Setting up NEW player for video item \(item.id)...")

        guard let url = item.imageUrl else {
            Self.logger.error("[Manager] Cannot setup player for item \(item.id): Invalid URL.")
            return
        }

        let newPlayer = AVPlayer(url: url)
        // Assign to published properties AFTER configuration
        let initialMute: Bool
        if let transientMute = settings.transientSessionMuteState {
            initialMute = transientMute
            Self.logger.info("[Manager] Player initial mute state for item \(item.id) set from TRANSIENT session state: \(initialMute)")
        } else {
            initialMute = settings.isVideoMuted
            settings.transientSessionMuteState = initialMute // Initialize transient state
            Self.logger.info("[Manager] Player initial mute state for item \(item.id) set from PERSISTED setting: \(initialMute). Transient session state initialized.")
        }
        newPlayer.isMuted = initialMute

        // Assign player and ID *before* setting up observers that might capture them
        self.player = newPlayer
        self.playerItemID = item.id

        setupObservers(for: newPlayer, item: item)

        // Only auto-play if NOT initially entering fullscreen
        if !isFullscreen {
            newPlayer.play()
            Self.logger.debug("[Manager] Player started (Autoplay) for item \(item.id)")
        } else {
             Self.logger.debug("[Manager] Skipping initial play because isFullscreen is true.")
        }
    }

    /// Sets up the necessary observers. Updates transientSessionMuteState on player changes.
    @MainActor
    private func setupObservers(for player: AVPlayer, item: Item) {
        guard let settings = self.settings else {
             Self.logger.error("[Manager] Cannot setup observers: AppSettings not configured.")
             return
        }

        // Remove existing observers before adding new ones (safety check)
        removeObservers() // Ensures we don't double-observe

        // --- Mute State Observer (KVO) ---
        // Capture `settings` weakly. Use '_' for unused observedPlayer.
        self.muteObserver = player.observe(\.isMuted, options: [.new]) { [weak settings] _, change in // Use _
            Task { @MainActor [weak settings] in // Removed weak observedPlayer capture
                guard let settings = settings,
                      let newMutedState = change.newValue
                else { return }

                if settings.transientSessionMuteState != newMutedState {
                     settings.transientSessionMuteState = newMutedState
                     VideoPlayerManager.logger.info("[Manager] User changed mute via player controls. New state: \(newMutedState). Transient session state updated.")
                }
            }
        }
        Self.logger.debug("[Manager] Added mute KVO observer for item \(item.id).")

        // --- Playback End Observer (Notification Center) ---
        guard let playerItem = player.currentItem else {
            Self.logger.error("[Manager] Player has no currentItem for item \(item.id). Cannot add loop observer.")
            return
        }

        // Wrap handler in Task @MainActor
        self.loopObserver = NotificationCenter.default.addObserver(
            forName: .AVPlayerItemDidPlayToEndTime,
            object: playerItem,
            queue: nil // Let the Task handle the actor context
        ) { [weak self] notification in // Keep weak self capture here
             // Capture self weakly again inside the Task to address the Sendable warning
             Task { @MainActor [weak self, weak playerItem] in
                 guard let strongSelf = self, // Check if self still exists
                       let playerItem = playerItem,
                       let currentPlayer = strongSelf.player, // Access properties via strongSelf
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
        Self.logger.debug("[Manager] Added loop observer for item \(item.id).")
    }

    /// Stops playback, removes observers, and releases references to the current AVPlayer instance.
    /// Ensures cleanup happens on the main thread.
    @MainActor
    func cleanupPlayer() {
        let cleanupItemID = self.playerItemID ?? -1 // Capture ID before niling
        let hadPlayer = self.player != nil

        // Only log cleanup start if there's actually something to clean
        if hadPlayer || muteObserver != nil || loopObserver != nil {
             Self.logger.debug("[Manager] Cleaning up player state for item \(cleanupItemID)...")
        } else {
             Self.logger.trace("[Manager] CleanupPlayer called, but nothing to clean up.")
             return // Nothing to do
        }

        // --- Remove Observers FIRST ---
        removeObservers() // Calls invalidate/removeObserver internally

        // -----------------------------

        // Pause and release player instance *after* removing observers
        if let playerToCleanup = self.player {
            playerToCleanup.pause()
            self.player = nil // Release reference
            Self.logger.debug("[Manager] Player paused and released for item \(cleanupItemID).")
        }

        // Reset the item ID tracker
        self.playerItemID = nil

        Self.logger.debug("[Manager] Player state cleanup finished for item \(cleanupItemID).")
    }

    /// Removes observers without stopping the player. Used internally if needed.
    @MainActor
    private func removeObservers() {
        // Invalidate KVO observer
        if muteObserver != nil {
             muteObserver?.invalidate()
             muteObserver = nil
             Self.logger.trace("[Manager] Invalidated mute observer internally.")
        }
        // Remove Notification Center observer
        if let observer = loopObserver {
            NotificationCenter.default.removeObserver(observer)
            self.loopObserver = nil
            Self.logger.trace("[Manager] Removed loop observer internally.")
        }
    }


    deinit {
        // Capture observers BEFORE the Task/Dispatch
        let kvoObserver = self.muteObserver
        let ncObserver = self.loopObserver

        // Use Task @MainActor for cleanup to ensure thread safety with UIKit/AVKit components
        Task { @MainActor in
            if kvoObserver != nil {
                kvoObserver?.invalidate()
            }
            if let ncObserver = ncObserver {
                NotificationCenter.default.removeObserver(ncObserver)
            }
        }
        // Log directly using static logger (safe outside Task if logger is nonisolated)
         VideoPlayerManager.logger.debug("VideoPlayerManager deinit.")
    }
}
// --- END OF COMPLETE FILE ---
