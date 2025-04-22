// FlowLayout.swift
import SwiftUI

/// Ein Layout, das Unteransichten horizontal anordnet und bei Bedarf
/// in die nächste Zeile umbricht, wobei der Inhalt jeder Zeile zentriert wird.
struct FlowLayout: Layout {
    var horizontalSpacing: CGFloat = 6 // Horizontaler Abstand zwischen Elementen
    var verticalSpacing: CGFloat = 6   // Vertikaler Abstand zwischen Reihen

    // Berechnet die benötigte Größe für das gesamte Layout.
    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
        guard let availableWidth = proposal.width, !subviews.isEmpty else { return .zero }

        var currentHeight: CGFloat = 0
        var currentRowWidth: CGFloat = 0
        var rowMaxHeight: CGFloat = 0

        // Bestimme die Höhen der einzelnen Reihen
        var rowHeights: [CGFloat] = []

        for subview in subviews {
            let subviewSize = subview.sizeThatFits(.unspecified)

            // Passt es in die aktuelle Reihe?
            if currentRowWidth + subviewSize.width + (currentRowWidth == 0 ? 0 : horizontalSpacing) <= availableWidth {
                // Ja: Füge zur Reihe hinzu
                currentRowWidth += subviewSize.width + (currentRowWidth == 0 ? 0 : horizontalSpacing)
                rowMaxHeight = max(rowMaxHeight, subviewSize.height)
            } else {
                // Nein: Schließe aktuelle Reihe ab und beginne neue
                rowHeights.append(rowMaxHeight) // Höhe der vollen Reihe speichern
                currentRowWidth = subviewSize.width
                rowMaxHeight = subviewSize.height
            }
        }
        rowHeights.append(rowMaxHeight) // Höhe der letzten Reihe speichern

        // Gesamthöhe berechnen
        currentHeight = rowHeights.reduce(0, +) + max(0, CGFloat(rowHeights.count - 1)) * verticalSpacing

        return CGSize(width: availableWidth, height: currentHeight)
    }

    // Platziert die Unteransichten innerhalb der gegebenen Grenzen.
    func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) {
        guard !subviews.isEmpty else { return }

        // Schritt 1: Bestimme, welche Subviews in welche Reihe gehören und deren Höhen
        var rowLayouts: [[(subview: LayoutSubviews.Element, size: CGSize)]] = []
        var currentRowItems: [(subview: LayoutSubviews.Element, size: CGSize)] = []
        var currentRowWidth: CGFloat = 0
        var rowHeights: [CGFloat] = []
        var currentRowMaxHeight: CGFloat = 0

        for subview in subviews {
            let subviewSize = subview.sizeThatFits(.unspecified)
            let effectiveSpacing = currentRowItems.isEmpty ? 0 : horizontalSpacing

            if currentRowWidth + effectiveSpacing + subviewSize.width <= bounds.width {
                currentRowWidth += effectiveSpacing + subviewSize.width
                currentRowMaxHeight = max(currentRowMaxHeight, subviewSize.height)
                currentRowItems.append((subview, subviewSize))
            } else {
                // Schließe aktuelle Reihe ab
                rowLayouts.append(currentRowItems)
                rowHeights.append(currentRowMaxHeight)

                // Beginne neue Reihe
                currentRowItems = [(subview, subviewSize)]
                currentRowWidth = subviewSize.width
                currentRowMaxHeight = subviewSize.height
            }
        }
        // Füge die letzte (möglicherweise unvollständige) Reihe hinzu
        if !currentRowItems.isEmpty {
            rowLayouts.append(currentRowItems)
            rowHeights.append(currentRowMaxHeight)
        }

        // Schritt 2: Platziere die Reihen zentriert
        var currentY = bounds.minY
        for rowIndex in 0..<rowLayouts.count {
            let rowContent = rowLayouts[rowIndex]
            let rowHeight = rowHeights[rowIndex]
            // Berechne die Gesamtbreite dieser spezifischen Reihe
            let currentLineWidth = rowContent.reduce(0) { $0 + $1.size.width } + max(0, CGFloat(rowContent.count - 1) * horizontalSpacing)
            // Berechne den Startpunkt X für die Zentrierung
            var currentX = bounds.minX + (bounds.width - currentLineWidth) / 2

            // Platziere die Elemente dieser Reihe
            for (subview, size) in rowContent {
                let viewProposal = ProposedViewSize(width: size.width, height: size.height)
                // Platziere am oberen Rand der Zeile, horizontal zentriert als Reihe
                subview.place(at: CGPoint(x: currentX, y: currentY), anchor: .topLeading, proposal: viewProposal)
                currentX += size.width + horizontalSpacing
            }
            // Gehe zur Y-Position der nächsten Reihe
            currentY += rowHeight + verticalSpacing
        }
    }
}
