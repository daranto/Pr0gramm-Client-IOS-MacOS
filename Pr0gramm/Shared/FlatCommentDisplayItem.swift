// Pr0gramm/Pr0gramm/Shared/FlatCommentDisplayItem.swift
// --- START OF COMPLETE FILE ---

import Foundation

/// Represents a single comment ready for display in a flat list (LazyVStack),
/// including its indentation level and whether it has children.
struct FlatCommentDisplayItem: Identifiable {
    let id: Int // Use original comment ID
    let comment: ItemComment
    let level: Int // Indentation level (0 for top-level)
    let hasChildren: Bool // Indicates if this comment has any direct replies in the original hierarchy
}
// --- END OF COMPLETE FILE ---
