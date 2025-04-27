// Pr0gramm/Pr0gramm/Features/MediaManagement/VideoPlayerManager.swift
// --- START OF COMPLETE FILE ---

// VideoPlayerManager.swift
import Foundation
import AVKit
import Combine
import os

/// Manages the lifecycle and state of the single AVPlayer instance used across the PagedDetailView.
/// This ensures proper cleanup even when the owning view's state changes rapidly.
@MainActor
class VideoPlayerManager: ObservableObject {
    private static let logger = Logger(subsystem: Bundle.main.bundleIdentifier!, category: "VideoPlayerManager")

    // MARK: - Published Player State
    @Published private(set) var player: AVPlayer? = nil
    @Published private(set) var playerItemID: Int? = nil

    // MARK: - Private Observer Properties
    private var muteObserver: NSKeyValueObservation? = nil
    private var loopObserver: NSObjectProtocol? = nil

    // MARK: - Internal State for Session Mute (REMOVED)
    // private var sessionMuteState: Bool? = nil // REMOVED

    // MARK: - Dependencies
    private weak var settings: AppSettings?

    /// Configures the manager with necessary dependencies after initialization.
    func configure(settings: AppSettings) {
        self.settings = settings
        Self.logger.debug("VideoPlayerManager configured with AppSettings.")
        // Resetting session state is now handled by PagedDetailView's scenePhase observer
    }

    /// Creates a new AVPlayer for the given video item or ensures the existing one plays if it's for the same item.
    /// Cleans up any previously active player. Reads transientSessionMuteState first, then isVideoMuted.
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

        guard playerItemID != item.id else {
            Self.logger.debug("[Manager] Player already exists for video item \(item.id). Ensuring it plays.")
            if player?.timeControlStatus != .playing { player?.play() }
            // Ensure existing player respects transient session state if it exists
            if let transientMute = settings.transientSessionMuteState, player?.isMuted != transientMute {
                Self.logger.trace("[Manager] Applying transient session mute state (\(transientMute)) to existing player for item \(item.id).")
                player?.isMuted = transientMute
            } else if settings.transientSessionMuteState == nil && player?.isMuted != settings.isVideoMuted {
                // If transient is nil, ensure it matches the persisted setting
                Self.logger.trace("[Manager] Applying persisted mute state (\(settings.isVideoMuted)) to existing player for item \(item.id) as transient state is nil.")
                player?.isMuted = settings.isVideoMuted
            }
            return
        }

        cleanupPlayer()
        Self.logger.debug("[Manager] Setting up player for video item \(item.id)...")

        guard let url = item.imageUrl else {
            Self.logger.error("[Manager] Cannot setup player for item \(item.id): Invalid URL.")
            return
        }

        let newPlayer = AVPlayer(url: url)
        self.player = newPlayer
        self.playerItemID = item.id

        // Set initial mute state: Prioritize transient state, then persisted setting
        let initialMute: Bool
        if let transientMute = settings.transientSessionMuteState {
            initialMute = transientMute
            Self.logger.info("[Manager] Player initial mute state for item \(item.id) set from TRANSIENT session state: \(initialMute)")
        } else {
            initialMute = settings.isVideoMuted
            // IMPORTANT: Store the initial state from persisted setting into the transient one
            // if the transient one was nil. This initializes the session state.
            settings.transientSessionMuteState = initialMute
            Self.logger.info("[Manager] Player initial mute state for item \(item.id) set from PERSISTED setting: \(initialMute). Transient session state initialized.")
        }
        newPlayer.isMuted = initialMute

        setupObservers(for: newPlayer, item: item)

        if !isFullscreen {
            newPlayer.play()
            Self.logger.debug("[Manager] Player started (Autoplay) for item \(item.id)")
        } else {
             Self.logger.debug("[Manager] Skipping initial play because isFullscreen is true.")
        }
    }

    /// Sets up the necessary observers. Updates transientSessionMuteState on player changes.
    private func setupObservers(for player: AVPlayer, item: Item) {
        guard let settings = self.settings else { return } // Need settings to update transient state

        // --- Mute State Observer (KVO) ---
        self.muteObserver = player.observe(\.isMuted, options: [.new]) { [weak self, weak settings] observedPlayer, change in
            // Capture settings weakly as well
            guard let self = self, let settings = settings,
                  let newMutedState = change.newValue,
                  observedPlayer == self.player,
                  self.playerItemID == item.id
            else { return }

            // Update the transient session state in AppSettings directly
            if settings.transientSessionMuteState != newMutedState {
                 settings.transientSessionMuteState = newMutedState
                 Self.logger.info("[Manager] User changed mute via player controls for item \(item.id). New state: \(newMutedState). Transient session state updated.")
            } else {
                 Self.logger.trace("[Manager] Player mute KVO fired, but transient session state already matches (\(newMutedState)). No state change.")
            }
        }
        Self.logger.debug("[Manager] Added mute KVO observer for item \(item.id).")

        // --- Playback End Observer (Notification Center) ---
        guard let playerItem = player.currentItem else {
            Self.logger.error("[Manager] Player has no currentItem for item \(item.id). Cannot add loop observer.")
            return
        }
        self.loopObserver = NotificationCenter.default.addObserver(
            forName: .AVPlayerItemDidPlayToEndTime,
            object: playerItem,
            queue: .main
        ) { [weak self] notification in
             guard let self = self,
                   let currentPlayer = self.player,
                   (notification.object as? AVPlayerItem) == currentPlayer.currentItem,
                   self.playerItemID == item.id
             else { return }

             Self.logger.debug("[Manager] Video did play to end time for item \(item.id). Seeking to zero and replaying.")
             currentPlayer.seek(to: .zero)
             currentPlayer.play()
         }
        Self.logger.debug("[Manager] Added loop observer for item \(item.id).")
    }

    /// Stops playback, removes observers, and releases references to the current AVPlayer instance.
    func cleanupPlayer() {
        guard player != nil || muteObserver != nil || loopObserver != nil else {
             Self.logger.trace("[Manager] CleanupPlayer called, but nothing to clean up (player or observers already nil).")
             return
        }
        let cleanupItemID = self.playerItemID ?? -1
        Self.logger.debug("[Manager] Cleaning up player state for item \(cleanupItemID)...")
        muteObserver?.invalidate(); muteObserver = nil
        if let observer = loopObserver { NotificationCenter.default.removeObserver(observer); self.loopObserver = nil }
        player?.pause()
        Self.logger.debug("[Manager] Player paused for item \(cleanupItemID).")
        player = nil
        playerItemID = nil
        // transientSessionMuteState remains in AppSettings

        Self.logger.debug("[Manager] Player state cleanup finished for item \(cleanupItemID). References set to nil.")
    }

    /// Removes observers without stopping the player.
    private func removeObservers() {
        muteObserver?.invalidate(); muteObserver = nil
        if let observer = loopObserver { NotificationCenter.default.removeObserver(observer); self.loopObserver = nil }
        Self.logger.debug("[Manager] Removed player observers.")
    }

    // --- REMOVED resetMuteStateFromSettings() ---
    // func resetMuteStateFromSettings() { ... }
    // -------------------------------------------

    deinit {
        Self.logger.debug("VideoPlayerManager deinit. Explicit cleanup should happen in View's onDisappear.")
        muteObserver?.invalidate()
        if let observer = loopObserver { NotificationCenter.default.removeObserver(observer) }
    }
}
// --- END OF COMPLETE FILE ---
