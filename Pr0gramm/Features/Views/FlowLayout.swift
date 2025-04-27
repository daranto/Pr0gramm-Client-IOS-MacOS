import SwiftUI

/// A custom SwiftUI `Layout` container that arranges its subviews horizontally,
/// wrapping them to the next line when the available width is exceeded.
/// Each row's content is horizontally centered within the layout bounds.
struct FlowLayout: Layout {
    /// Horizontal spacing between items in the same row.
    var horizontalSpacing: CGFloat = 6
    /// Vertical spacing between rows.
    var verticalSpacing: CGFloat = 6

    /// Calculates the total size required by the layout given a proposed size.
    /// - Returns: The calculated `CGSize`. Returns `.zero` if the proposed width is insufficient or there are no subviews.
    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
        // Ensure there's a valid proposed width and subviews to layout.
        guard let availableWidth = proposal.width, availableWidth > 10, !subviews.isEmpty else {
            return .zero
        }

        var currentHeight: CGFloat = 0
        var currentRowWidth: CGFloat = 0
        var rowMaxHeight: CGFloat = 0 // Tracks the max height of the current row being calculated
        var rowHeights: [CGFloat] = [] // Stores the max height of each completed row

        // Iterate through subviews to determine row breaks and heights
        for subview in subviews {
            let subviewSize = subview.sizeThatFits(.unspecified) // Get the ideal size of the subview
            let spacing = currentRowWidth == 0 ? 0 : horizontalSpacing // Add spacing only after the first item in a row

            // Check if the subview fits in the current row
            if currentRowWidth + spacing + subviewSize.width <= availableWidth {
                // Fits: Add to current row width and update max height
                currentRowWidth += spacing + subviewSize.width
                rowMaxHeight = max(rowMaxHeight, subviewSize.height)
            } else {
                // Doesn't fit: Finalize the current row and start a new one
                rowHeights.append(rowMaxHeight) // Store the height of the completed row
                currentRowWidth = subviewSize.width // Reset row width
                rowMaxHeight = subviewSize.height // Reset row max height
            }
        }
        // Add the height of the last row
        rowHeights.append(rowMaxHeight)

        // Calculate total height: sum of row heights + vertical spacing between rows
        currentHeight = rowHeights.reduce(0, +) + max(0, CGFloat(rowHeights.count - 1)) * verticalSpacing

        // Return the required size, ensuring height is non-negative
        return CGSize(width: availableWidth, height: max(0, currentHeight))
    }

    /// Places the subviews within the specified bounds according to the flow layout logic.
    func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) {
        // Ensure valid bounds and subviews exist before attempting placement
        guard bounds.width > 10, !subviews.isEmpty else {
            return
        }

        // --- Step 1: Arrange subviews into rows ---
        var rowLayouts: [[(subview: LayoutSubviews.Element, size: CGSize)]] = [] // Stores subviews and their sizes per row
        var currentRowItems: [(subview: LayoutSubviews.Element, size: CGSize)] = []
        var currentRowWidth: CGFloat = 0
        var rowHeights: [CGFloat] = [] // Stores the calculated max height for each row
        var currentRowMaxHeight: CGFloat = 0

        // Group subviews into rows based on available width (bounds.width)
        for subview in subviews {
            let subviewSize = subview.sizeThatFits(.unspecified)
            let effectiveSpacing = currentRowItems.isEmpty ? 0 : horizontalSpacing

            // Check if the subview fits in the current row within the layout bounds
            if currentRowWidth + effectiveSpacing + subviewSize.width <= bounds.width {
                currentRowWidth += effectiveSpacing + subviewSize.width
                currentRowMaxHeight = max(currentRowMaxHeight, subviewSize.height)
                currentRowItems.append((subview, subviewSize))
            } else {
                // Doesn't fit: Finalize the current row, store its layout and height
                rowLayouts.append(currentRowItems)
                rowHeights.append(currentRowMaxHeight)
                // Start a new row with the current subview
                currentRowItems = [(subview, subviewSize)]
                currentRowWidth = subviewSize.width
                currentRowMaxHeight = subviewSize.height
            }
        }
        // Add the last row if it contains items
        if !currentRowItems.isEmpty {
            rowLayouts.append(currentRowItems)
            rowHeights.append(currentRowMaxHeight)
        }

        // --- Step 2: Place the rows, centering content horizontally ---
        var currentY = bounds.minY // Start placing from the top of the bounds
        for rowIndex in 0..<rowLayouts.count {
            let rowContent = rowLayouts[rowIndex]
            let rowHeight = rowHeights[rowIndex]
            // Calculate the total width occupied by the content of this row
            let currentLineWidth = rowContent.reduce(0) { $0 + $1.size.width } + max(0, CGFloat(rowContent.count - 1) * horizontalSpacing)
            // Ensure the available width for centering calculation is non-negative
            let availableRowWidth = max(0, bounds.width)
            // Calculate the starting X position to center the row's content
            var currentX = bounds.minX + max(0, (availableRowWidth - currentLineWidth) / 2)

            // Place each subview in the current row
            for (subview, size) in rowContent {
                 // Ensure the proposed size for placement is non-negative
                 let viewProposal = ProposedViewSize(width: max(0, size.width), height: max(0, size.height))
                 // Place the subview at the calculated position
                 // Check for finite coordinates as a safety measure
                 if currentX.isFinite && currentY.isFinite {
                     subview.place(at: CGPoint(x: currentX, y: currentY), anchor: .topLeading, proposal: viewProposal)
                 }
                 // Move the X cursor for the next subview
                currentX += size.width + horizontalSpacing
            }
            // Move the Y cursor down for the next row
            currentY += rowHeight + verticalSpacing
        }
    }
}
