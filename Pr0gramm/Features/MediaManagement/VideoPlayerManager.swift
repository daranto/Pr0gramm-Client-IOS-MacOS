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
    /// The single AVPlayer instance managed by this object. Updated via `setupPlayerIfNeeded`.
    @Published private(set) var player: AVPlayer? = nil
    /// The ID of the pr0gramm Item currently associated with the `player`. Nil if no player is active.
    @Published private(set) var playerItemID: Int? = nil

    // MARK: - Private Observer Properties
    /// KVO observer for the player's mute state.
    private var muteObserver: NSKeyValueObservation? = nil
    /// Notification observer for when the player item reaches its end (for looping).
    private var loopObserver: NSObjectProtocol? = nil

    // MARK: - Dependencies
    /// Reference to global app settings, needed for initial mute state. Weak to avoid potential cycles if needed, though unlikely here.
    private weak var settings: AppSettings?

    /// Configures the manager with necessary dependencies after initialization.
    /// - Parameter settings: The global AppSettings instance.
    func configure(settings: AppSettings) {
        self.settings = settings
        Self.logger.debug("VideoPlayerManager configured with AppSettings.")
    }

    /// Creates a new AVPlayer for the given video item or ensures the existing one plays if it's for the same item.
    /// Cleans up any previously active player.
    /// - Parameters:
    ///   - item: The `Item` to setup the player for. If not a video, any existing player is cleaned up.
    ///   - isFullscreen: Indicates if the context is currently fullscreen (affects initial autoplay).
    func setupPlayerIfNeeded(for item: Item, isFullscreen: Bool) {
        // If the target item is not a video, ensure any existing player is cleaned up.
        guard item.isVideo else {
            if player != nil { // Only cleanup if a player actually exists
                Self.logger.debug("[Manager] New item \(item.id) is not video. Cleaning up existing player (if any).")
                cleanupPlayer()
            } else {
                Self.logger.trace("[Manager] New item \(item.id) is not video. No existing player to clean up.")
            }
            return
        }

        // If the player already exists for this *exact* item, just ensure it's playing.
        guard playerItemID != item.id else {
            Self.logger.debug("[Manager] Player already exists for video item \(item.id). Ensuring it plays.")
            if player?.timeControlStatus != .playing {
                player?.play()
            }
            return
        }

        // --- A new video item needs a player ---
        cleanupPlayer() // Clean up the previous player first.
        Self.logger.debug("[Manager] Setting up player for video item \(item.id)...")

        guard let url = item.imageUrl else {
            Self.logger.error("[Manager] Cannot setup player for item \(item.id): Invalid URL.")
            return
        }

        // Create the new player instance
        let newPlayer = AVPlayer(url: url)
        // Update the published properties - this triggers UI updates if views observe them.
        self.player = newPlayer
        self.playerItemID = item.id // Associate the player with this item ID

        // Set initial mute state based on AppSettings
        if let settings = settings {
            newPlayer.isMuted = settings.isVideoMuted
            Self.logger.info("[Manager] Player initial mute state for item \(item.id) set to: \(settings.isVideoMuted)")
        } else {
             Self.logger.warning("[Manager] AppSettings not configured. Cannot set initial mute state. Defaulting to muted.")
             newPlayer.isMuted = true // Safe default
        }

        // Set up KVO and Notification observers for the new player
        setupObservers(for: newPlayer, item: item)

        // Start playback unless we are currently in fullscreen mode
        if !isFullscreen {
            newPlayer.play()
            Self.logger.debug("[Manager] Player started (Autoplay) for item \(item.id)")
        } else {
             Self.logger.debug("[Manager] Skipping initial play because isFullscreen is true.")
        }
    }

    /// Sets up the necessary observers (mute state, playback end) for the given player and item.
    private func setupObservers(for player: AVPlayer, item: Item) {
        // --- Mute State Observer (KVO) ---
        self.muteObserver = player.observe(\.isMuted, options: [.new]) { [weak self] observedPlayer, change in
            // Use weak self to avoid retain cycles
            guard let self = self,
                  let newMutedState = change.newValue,
                  observedPlayer == self.player, // Ensure observation is for the *current* player instance
                  self.playerItemID == item.id    // Ensure player still belongs to the correct item
            else { return }

            // Update global settings if the mute state was changed via player controls
            Task { @MainActor in
                if self.settings?.isVideoMuted != newMutedState {
                    Self.logger.info("[Manager] User changed mute via player controls for item \(item.id). New state: \(newMutedState). Updating global setting.")
                    self.settings?.isVideoMuted = newMutedState
                }
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
            object: playerItem, // Important: Observe only this specific player item
            queue: .main // Ensure handler runs on main thread
        ) { [weak self] notification in
             // Use weak self and guard checks to ensure context is still valid
             guard let self = self,
                   let currentPlayer = self.player, // Check if manager still has an active player
                   (notification.object as? AVPlayerItem) == currentPlayer.currentItem, // Is notification for the active player's item?
                   self.playerItemID == item.id // Does the player still belong to the item that finished?
             else { return }

             Self.logger.debug("[Manager] Video did play to end time for item \(item.id). Seeking to zero and replaying.")
             currentPlayer.seek(to: .zero)
             currentPlayer.play()
         }
        Self.logger.debug("[Manager] Added loop observer for item \(item.id).")
    }

    /// Stops playback, removes observers, and releases references to the current AVPlayer instance.
    /// This is the central cleanup method, intended to be called explicitly (e.g., from onDisappear).
    func cleanupPlayer() {
        // Check if there is actually anything to clean up
        guard player != nil || muteObserver != nil || loopObserver != nil else {
             Self.logger.trace("[Manager] CleanupPlayer called, but nothing to clean up (player or observers already nil).")
             return
        }

        let cleanupItemID = self.playerItemID ?? -1 // Log which item's player is being cleaned
        Self.logger.debug("[Manager] Cleaning up player state for item \(cleanupItemID)...")

        // 1. Invalidate KVO observer
        muteObserver?.invalidate()
        muteObserver = nil // Release reference

        // 2. Remove Notification Center observer
        if let observer = loopObserver {
            NotificationCenter.default.removeObserver(observer)
            self.loopObserver = nil // Release reference
        }

        // 3. Explicitly pause the player
        player?.pause()
        Self.logger.debug("[Manager] Player paused for item \(cleanupItemID).")

        // 4. Release references to player and item ID - triggers @Published updates
        player = nil
        playerItemID = nil

        Self.logger.debug("[Manager] Player state cleanup finished for item \(cleanupItemID). References set to nil.")
    }

    /// Removes observers without stopping the player. Used internally before switching players.
    private func removeObservers() {
        muteObserver?.invalidate(); muteObserver = nil
        if let observer = loopObserver { NotificationCenter.default.removeObserver(observer); self.loopObserver = nil }
        Self.logger.debug("[Manager] Removed player observers.")
    }

    deinit {
        Self.logger.debug("VideoPlayerManager deinit. Explicit cleanup should happen in View's onDisappear.")
    }
}
