/// Represents a comment prepared for hierarchical display, including its children.
struct DisplayComment: Identifiable {
    let id: Int // Use the original comment's ID
    let comment: ItemComment
    let children: [DisplayComment] // Recursively holds child comments
}
