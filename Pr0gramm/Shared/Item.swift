import Foundation

/// Represents a single media item (post) from the pr0gramm API.
struct Item: Codable, Identifiable, Hashable {
    let id: Int
    let promoted: Int? // ID used for pagination in the 'promoted' feed, nil for 'new' feed
    let userId: Int
    let down: Int // Downvotes
    let up: Int // Upvotes
    let created: Int // Unix Timestamp of creation
    let image: String // Filename of the image/video (relative path)
    let thumb: String // Filename of the thumbnail (relative path)
    let fullsize: String? // Filename of the full-size image (if available, relative path)
    let preview: String? // Filename of the preview image (often used for videos, relative path)
    let width: Int // Original width in pixels
    let height: Int // Original height in pixels
    let audio: Bool // Indicates if a video has audio
    let source: String? // Optional source URL provided by the uploader
    let flags: Int   // Content flags (SFW=1, NSFW=2, NSFL=4, NSFP=8, POL=16) combined integer
    let user: String // Username of the uploader
    let mark: Int // Uploader's mark/rank (raw integer value)
    let repost: Bool? // Indicates if the item is potentially a repost (API determines this)
    let variants: [ItemVariant]? // Available video variants (different codecs/resolutions)
    var favorited: Bool? // Local state indicating if the *current user* has favorited this item. Updated by app logic, not directly from `items/get`.

    // MARK: - Computed Properties

    /// Checks if the item represents a video based on its file extension.
    var isVideo: Bool {
        // Note: WEBM is not natively supported by AVPlayer on iOS. Handling might be needed.
        image.lowercased().hasSuffix(".mp4") || image.lowercased().hasSuffix(".webm")
    }

    /// Constructs the full URL for the item's thumbnail image.
    var thumbnailUrl: URL? {
        // Thumbnails are served from a specific subdomain.
        return URL(string: "https://thumb.pr0gramm.com/\(thumb)")
    }

    /// Constructs the full URL for the main media content (image or video).
    /// For videos, this usually points to the highest quality MP4 variant by default.
    /// Future logic could select a specific variant from `variants` based on settings or network conditions.
    var imageUrl: URL? {
        if isVideo {
            // Videos are served from the 'vid' subdomain.
            return URL(string: "https://vid.pr0gramm.com/\(image)")
        } else {
            // Images are served from the 'img' subdomain.
            return URL(string: "https://img.pr0gramm.com/\(image)")
        }
    }

    /// Converts the `created` Unix timestamp to a `Date` object.
    var creationDate: Date {
        return Date(timeIntervalSince1970: TimeInterval(created))
    }
}

/// Represents a single video variant available for an `Item`.
struct ItemVariant: Codable, Hashable {
    let name: String     // Identifier for the variant (e.g., "vp9s", "h264", "source")
    let path: String     // Relative path to the video file on the 'vid' subdomain
    let mimeType: String // MIME type (e.g., "video/mp4", "video/webm")
    let codec: String    // Video codec (e.g., "vp9", "h264")
    let width: Int
    let height: Int
    let bitRate: Double? // Video bitrate, can be nil
    let fileSize: Int?   // File size in bytes, can be nil

    /// Constructs the full URL for this specific video variant.
    var variantUrl: URL? {
        return URL(string: "https://vid.pr0gramm.com\(path)")
    }
}
