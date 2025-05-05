// Pr0gramm/Pr0gramm/Shared/VTTParser.swift
// --- START OF COMPLETE FILE ---

import Foundation
import os // For logging

/// A simple parser for WebVTT (.vtt) subtitle files.
struct VTTParser {
    private static let logger = Logger(subsystem: Bundle.main.bundleIdentifier!, category: "VTTParser")

    /// Parses the content of a VTT file string into an array of SubtitleCue objects.
    /// - Parameter vttString: The raw string content of the VTT file.
    /// - Returns: An array of `SubtitleCue` objects, sorted by start time.
    static func parse(_ vttString: String) -> [SubtitleCue] {
        var cues: [SubtitleCue] = []
        let lines = vttString.components(separatedBy: .newlines)
        var currentStartTime: TimeInterval?
        var currentEndTime: TimeInterval?
        var currentTextLines: [String] = []
        var processingCue = false

        // Basic validation: Check for WEBVTT header
        guard lines.first?.trimmingCharacters(in: .whitespacesAndNewlines) == "WEBVTT" else {
            logger.warning("Invalid VTT file: Missing 'WEBVTT' header.")
            return []
        }

        for line in lines {
            let trimmedLine = line.trimmingCharacters(in: .whitespacesAndNewlines)

            if trimmedLine.contains("-->") {
                // Found a timestamp line
                if processingCue, let start = currentStartTime, let end = currentEndTime, !currentTextLines.isEmpty {
                    cues.append(SubtitleCue(startTime: start, endTime: end, text: currentTextLines.joined(separator: "\n")))
                }

                // Reset for the new cue
                currentTextLines = []
                processingCue = true

                // Parse timestamps
                let components = trimmedLine.components(separatedBy: "-->")
                if components.count == 2 {
                    currentStartTime = parseTimestamp(components[0].trimmingCharacters(in: .whitespaces))
                    currentEndTime = parseTimestamp(components[1].trimmingCharacters(in: .whitespaces).components(separatedBy: .whitespaces).first ?? "")

                    if currentStartTime == nil || currentEndTime == nil {
                        logger.warning("Failed to parse timestamp line: '\(trimmedLine)'")
                        processingCue = false
                    }
                } else {
                    logger.warning("Invalid timestamp line format: '\(trimmedLine)'")
                    processingCue = false
                }

            } else if processingCue && !trimmedLine.isEmpty {
                // If we are processing a cue and the line is not empty, it's part of the text
                if Int(trimmedLine) == nil {
                    currentTextLines.append(trimmedLine)
                }
            } else if trimmedLine.isEmpty && processingCue {
                // An empty line signifies the end of the text for the current cue
                if let start = currentStartTime, let end = currentEndTime, !currentTextLines.isEmpty {
                    cues.append(SubtitleCue(startTime: start, endTime: end, text: currentTextLines.joined(separator: "\n")))
                }
                // Reset for the next potential cue block
                processingCue = false
                currentStartTime = nil
                currentEndTime = nil
                currentTextLines = []
            }
        }

        // Add the last cue if it was being processed
        if processingCue, let start = currentStartTime, let end = currentEndTime, !currentTextLines.isEmpty {
            cues.append(SubtitleCue(startTime: start, endTime: end, text: currentTextLines.joined(separator: "\n")))
        }

        logger.info("Parsed \(cues.count) subtitle cues from VTT data.")
        return cues.sorted { $0.startTime < $1.startTime }
    }

    /// Parses a VTT timestamp string (e.g., "00:00:05.500" or "00:05.500") into seconds.
    private static func parseTimestamp(_ timestamp: String) -> TimeInterval? {
        let components = timestamp.split(separator: ":").map(String.init)
        var seconds: TimeInterval = 0.0

        // --- FIX: Remove do-catch as Double() doesn't throw ---
        if components.count == 3 { // Format HH:MM:SS.ms
            guard let hours = Double(components[0]),
                  let minutes = Double(components[1]),
                  let secs = Double(components[2].replacingOccurrences(of: ",", with: "."))
            else { return nil }
            seconds = (hours * 3600) + (minutes * 60) + secs
        } else if components.count == 2 { // Format MM:SS.ms
            guard let minutes = Double(components[0]),
                  let secs = Double(components[1].replacingOccurrences(of: ",", with: "."))
            else { return nil }
            seconds = (minutes * 60) + secs
        } else {
            return nil // Invalid format
        }
        return seconds
        // --- END FIX ---
    }
}
// --- END OF COMPLETE FILE ---
