// Pr0gramm/Pr0gramm/Features/Views/Pr0Tok/ShareHelper.swift

import Foundation
import UIKit
import Kingfisher
import os

/// Result type for share preparation
enum SharePrepResult {
    case success(ShareableItemWrapper)
    case failure(String)
}

/// Helper for preparing and sharing media items
struct ShareHelper {
    private static let logger = Logger(subsystem: Bundle.main.bundleIdentifier!, category: "ShareHelper")
    
    /// Prepares media (image or video) for sharing
    /// - Parameters:
    ///   - item: The item to share
    /// - Returns: SharePrepResult with wrapper or error message
    @MainActor
    static func prepareMediaForSharing(item: Item) async -> SharePrepResult {
        guard let mediaUrl = item.imageUrl else {
            logger.error("Cannot share media: URL is nil for item \(item.id)")
            return .failure("Medien-URL nicht verfügbar.")
        }
        
        if item.isVideo {
            return await prepareVideoForSharing(item: item, mediaUrl: mediaUrl)
        } else {
            return await prepareImageForSharing(mediaUrl: mediaUrl)
        }
    }
    
    @MainActor
    private static func prepareVideoForSharing(item: Item, mediaUrl: URL) async -> SharePrepResult {
        do {
            let temporaryDirectory = FileManager.default.temporaryDirectory
            let fileName = mediaUrl.lastPathComponent
            let localUrl = temporaryDirectory.appendingPathComponent(fileName)
            
            let (downloadedUrl, response) = try await URLSession.shared.download(from: mediaUrl)
            guard let httpResponse = response as? HTTPURLResponse,
                  (200..<300).contains(httpResponse.statusCode) else {
                logger.error("Video download failed with status code: \((response as? HTTPURLResponse)?.statusCode ?? -1)")
                return .failure("Video-Download fehlgeschlagen (Code: \((response as? HTTPURLResponse)?.statusCode ?? -1)).")
            }
            
            if FileManager.default.fileExists(atPath: localUrl.path) {
                try FileManager.default.removeItem(at: localUrl)
            }
            try FileManager.default.moveItem(at: downloadedUrl, to: localUrl)
            
            logger.info("Video successfully prepared for sharing: \(item.id)")
            return .success(ShareableItemWrapper(itemsToShare: [localUrl], temporaryFileUrlToDelete: localUrl))
        } catch {
            logger.error("Video download/preparation failed for item \(item.id): \(error.localizedDescription)")
            return .success(ShareableItemWrapper(itemsToShare: [mediaUrl]))
        }
    }
    
    @MainActor
    private static func prepareImageForSharing(mediaUrl: URL) async -> SharePrepResult {
        let result: Result<ImageLoadingResult, KingfisherError> = await withCheckedContinuation { continuation in
            KingfisherManager.shared.downloader.downloadImage(with: mediaUrl, options: nil) { result in
                continuation.resume(returning: result)
            }
        }
        
        switch result {
        case .success(let imageLoadingResult):
            logger.info("Image successfully prepared for sharing")
            return .success(ShareableItemWrapper(itemsToShare: [imageLoadingResult.image]))
        case .failure(let error):
            if !error.isTaskCancelled && !error.isNotCurrentTask {
                logger.error("Image download failed: \(error.localizedDescription)")
                return .failure("Bild-Download fehlgeschlagen.")
            }
            logger.info("Image download cancelled or not current task")
            return .failure("Download abgebrochen.")
        }
    }
    
    /// Copies post link to clipboard
    /// - Parameter itemID: The item ID to create link for
    static func copyPostLink(for itemID: Int) {
        let urlString = "https://pr0gramm.com/new/\(itemID)"
        UIPasteboard.general.string = urlString
        logger.info("Copied Post-URL to clipboard: \(urlString)")
    }
    
    /// Copies direct media URL to clipboard
    /// - Parameter item: The item whose media URL should be copied
    static func copyMediaLink(for item: Item) -> Bool {
        if let urlString = item.imageUrl?.absoluteString {
            UIPasteboard.general.string = urlString
            logger.info("Copied Media-Link to clipboard: \(urlString)")
            return true
        } else {
            logger.warning("Failed to copy Media-Link: URL was nil for item \(item.id)")
            return false
        }
    }
    
    /// Deletes temporary file (used after sharing)
    /// - Parameter url: The URL of the temporary file to delete
    static func deleteTemporaryFile(at url: URL) {
        Task(priority: .background) {
            do {
                if FileManager.default.fileExists(atPath: url.path) {
                    try FileManager.default.removeItem(at: url)
                    logger.info("Deleted temporary file: \(url.path)")
                }
            } catch {
                logger.error("Error deleting temporary file \(url.path): \(error.localizedDescription)")
            }
        }
    }
}
