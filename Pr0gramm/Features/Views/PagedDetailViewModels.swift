// Pr0gramm/Pr0gramm/Features/Views/PagedDetailViewModels.swift

import Foundation

// MARK: - Sheet Targets

struct PreviewLinkTarget: Identifiable, Equatable {
    let itemID: Int
    let commentID: Int?
    var id: Int { itemID }

    static func == (lhs: PreviewLinkTarget, rhs: PreviewLinkTarget) -> Bool {
        lhs.itemID == rhs.itemID && lhs.commentID == rhs.commentID
    }
}

struct FullscreenImageTarget: Identifiable, Equatable {
    let item: Item
    var id: Int { item.id }
    
    static func == (lhs: FullscreenImageTarget, rhs: FullscreenImageTarget) -> Bool {
        lhs.item.id == rhs.item.id
    }
}

struct UserProfileSheetTarget: Identifiable, Equatable {
    let username: String
    var id: String { username }
}

struct CollectionSelectionSheetTarget: Identifiable, Equatable {
    let id = UUID()
    let item: Item

    static func == (lhs: CollectionSelectionSheetTarget, rhs: CollectionSelectionSheetTarget) -> Bool {
        lhs.id == rhs.id && lhs.item.id == rhs.item.id
    }
}

// MARK: - Cached Data Models

struct CachedItemDetails {
    let info: ItemsInfoResponse
    let sortedBy: CommentSortOrder
    let flatDisplayComments: [FlatCommentDisplayItem]
    let totalCommentCount: Int
}

struct ReplyTarget: Identifiable {
    let id = UUID()
    let itemId: Int
    let parentId: Int
}
