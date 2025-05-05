// Pr0gramm/Pr0gramm/Shared/SubtitleCue.swift
// --- START OF COMPLETE FILE ---

import Foundation

/// Represents a single parsed subtitle cue from a VTT file.
struct SubtitleCue: Identifiable {
    let id = UUID() // Unique identifier for ForEach loops if needed
    let startTime: TimeInterval // Start time in seconds
    let endTime: TimeInterval   // End time in seconds
    let text: String            // The subtitle text content
}
// --- END OF COMPLETE FILE ---
