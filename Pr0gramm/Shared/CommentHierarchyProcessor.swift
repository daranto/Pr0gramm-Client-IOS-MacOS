// Pr0gramm/Pr0gramm/Shared/CommentHierarchyProcessor.swift

import Foundation
import os

/// Processes comment hierarchies for flat display with collapsing support
struct CommentHierarchyProcessor {
    private static let logger = Logger(subsystem: Bundle.main.bundleIdentifier!, category: "CommentHierarchyProcessor")
    
    /// Prepares flat display list from hierarchical comments
    /// - Parameters:
    ///   - comments: Raw hierarchical comments
    ///   - sortOrder: Sort order for comments
    ///   - maxDepth: Maximum nesting depth
    /// - Returns: Flattened comment list for display
    static func prepareFlatDisplayComments(
        from comments: [ItemComment],
        sortedBy sortOrder: CommentSortOrder,
        maxDepth: Int
    ) -> [FlatCommentDisplayItem] {
        logger.debug("Preparing flat display comments (\(comments.count) raw), sort: \(sortOrder.displayName), depth: \(maxDepth).")
        let startTime = Date()
        
        var flatList: [FlatCommentDisplayItem] = []
        let childrenByParentId = Dictionary(grouping: comments.filter { $0.parent != nil && $0.parent != 0 }, by: { $0.parent! })
        let commentDict = Dictionary(uniqueKeysWithValues: comments.map { ($0.id, $0) })
        
        func traverse(commentId: Int, currentLevel: Int) {
            guard currentLevel <= maxDepth, let comment = commentDict[commentId] else { return }
            let children = childrenByParentId[commentId] ?? []
            let hasChildren = !children.isEmpty
            flatList.append(FlatCommentDisplayItem(id: comment.id, comment: comment, level: currentLevel, hasChildren: hasChildren))
            
            guard currentLevel < maxDepth else { return }
            
            let sortedChildren: [ItemComment]
            switch sortOrder {
            case .date:
                sortedChildren = children.sorted { $0.created < $1.created }
            case .score:
                sortedChildren = children.sorted { ($0.up - $0.down) > ($1.up - $1.down) }
            }
            sortedChildren.forEach { traverse(commentId: $0.id, currentLevel: currentLevel + 1) }
        }
        
        let topLevelComments = comments.filter { $0.parent == nil || $0.parent == 0 }
        let sortedTopLevelComments: [ItemComment]
        switch sortOrder {
        case .date:
            sortedTopLevelComments = topLevelComments.sorted { $0.created < $1.created }
        case .score:
            sortedTopLevelComments = topLevelComments.sorted { ($0.up - $0.down) > ($1.up - $1.down) }
        }
        sortedTopLevelComments.forEach { traverse(commentId: $0.id, currentLevel: 0) }
        
        let duration = Date().timeIntervalSince(startTime)
        logger.info("Finished preparing flat comments (\(flatList.count) items) in \(String(format: "%.3f", duration))s.")
        return flatList
    }
    
    /// Calculates visible comments after applying collapse state
    /// - Parameters:
    ///   - flatComments: Full flat comment list
    ///   - collapsedIDs: Set of collapsed comment IDs
    /// - Returns: Filtered list of visible comments
    static func calculateVisibleComments(
        from flatComments: [FlatCommentDisplayItem],
        collapsedIDs: Set<Int>
    ) -> [FlatCommentDisplayItem] {
        guard !collapsedIDs.isEmpty else { return flatComments }
        
        var visibleList: [FlatCommentDisplayItem] = []
        var nearestCollapsedAncestorLevel: [Int: Int] = [:]
        
        for item in flatComments {
            let currentLevel = item.level
            var isHiddenByAncestor = false
            
            if currentLevel > 0 {
                for ancestorLevel in 0..<currentLevel {
                    if nearestCollapsedAncestorLevel[ancestorLevel] != nil {
                        isHiddenByAncestor = true
                        nearestCollapsedAncestorLevel[currentLevel] = nearestCollapsedAncestorLevel[ancestorLevel]
                        break
                    }
                }
            }
            
            if isHiddenByAncestor { continue }
            visibleList.append(item)
            
            if collapsedIDs.contains(item.id) {
                nearestCollapsedAncestorLevel[currentLevel] = item.id
            } else {
                nearestCollapsedAncestorLevel.removeValue(forKey: currentLevel)
            }
            
            let keysToRemove = nearestCollapsedAncestorLevel.keys.filter { $0 > currentLevel }
            for key in keysToRemove {
                nearestCollapsedAncestorLevel.removeValue(forKey: key)
            }
        }
        
        return visibleList
    }
}
