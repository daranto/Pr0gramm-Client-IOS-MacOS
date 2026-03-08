// Pr0gramm/Pr0gramm/Shared/Pr0grammLinkParser.swift

import Foundation
import os

/// Utility for parsing pr0gramm.com URLs to extract item IDs and comment IDs
struct Pr0grammLinkParser {
    private static let logger = Logger(subsystem: Bundle.main.bundleIdentifier!, category: "Pr0grammLinkParser")
    
    /// Parses a pr0gramm.com URL and extracts the item ID and optional comment ID
    /// - Parameter url: The URL to parse
    /// - Returns: A tuple containing the item ID and optional comment ID, or nil if parsing fails
    static func parse(url: URL) -> (itemID: Int, commentID: Int?)? {
        guard let host = url.host?.lowercased(), (host == "pr0gramm.com" || host == "www.pr0gramm.com") else {
            return nil
        }

        let path = url.path
        let components = path.components(separatedBy: "/")
        var itemID: Int? = nil
        var commentID: Int? = nil

        // Try to extract from path components
        if let lastPathComponent = components.last {
            // Handle format: "12345:comment67890"
            if lastPathComponent.contains(":comment") {
                let parts = lastPathComponent.split(separator: ":")
                if parts.count == 2,
                   let idPart = Int(parts[0]),
                   parts[1].starts(with: "comment"),
                   let cID = Int(parts[1].dropFirst("comment".count)) {
                    itemID = idPart
                    commentID = cID
                }
            } else {
                // Handle format: "/new/12345" or "/top/12345" or just "/12345"
                var potentialItemIDIndex: Int? = nil
                if let idx = components.lastIndex(where: { $0 == "new" || $0 == "top" }), idx + 1 < components.count {
                    potentialItemIDIndex = idx + 1
                } else if components.count > 1 && Int(components.last!) != nil {
                    potentialItemIDIndex = components.count - 1
                }
                
                if let idx = potentialItemIDIndex, let id = Int(components[idx]) {
                    itemID = id
                }
            }
        }
        
        // Fallback: Try to extract from query parameters
        if itemID == nil, let queryItems = URLComponents(url: url, resolvingAgainstBaseURL: false)?.queryItems {
            for item in queryItems {
                if item.name == "id", let value = item.value, let id = Int(value) {
                    itemID = id
                    break
                }
            }
        }
        
        if let itemID = itemID {
            return (itemID, commentID)
        }

        logger.warning("Could not parse item or comment ID from pr0gramm link: \(url.absoluteString)")
        return nil
    }
}
