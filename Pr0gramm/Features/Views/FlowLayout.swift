// FlowLayout.swift
import SwiftUI

/// Ein Layout, das Unteransichten horizontal anordnet und bei Bedarf
/// in die nächste Zeile umbricht, wobei der Inhalt jeder Zeile zentriert wird.
struct FlowLayout: Layout {
    var horizontalSpacing: CGFloat = 6 // Horizontaler Abstand zwischen Elementen
    var verticalSpacing: CGFloat = 6   // Vertikaler Abstand zwischen Reihen

    // Berechnet die benötigte Größe für das gesamte Layout.
    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
        // --- Breitenprüfung HIER hinzugefügt ---
        // Wenn keine Breite vorgeschlagen wird oder sie sehr klein ist, gib Zero zurück.
        // Der Mindestwert (z.B. 10) verhindert ungültige Berechnungen bei extremen Größen.
        guard let availableWidth = proposal.width, availableWidth > 10, !subviews.isEmpty else { return .zero }
        // --- Ende Breitenprüfung ---

        var currentHeight: CGFloat = 0
        var currentRowWidth: CGFloat = 0
        var rowMaxHeight: CGFloat = 0
        var rowHeights: [CGFloat] = []

        for subview in subviews {
            let subviewSize = subview.sizeThatFits(.unspecified)
            if currentRowWidth + subviewSize.width + (currentRowWidth == 0 ? 0 : horizontalSpacing) <= availableWidth {
                currentRowWidth += subviewSize.width + (currentRowWidth == 0 ? 0 : horizontalSpacing)
                rowMaxHeight = max(rowMaxHeight, subviewSize.height)
            } else {
                rowHeights.append(rowMaxHeight)
                currentRowWidth = subviewSize.width
                rowMaxHeight = subviewSize.height
            }
        }
        rowHeights.append(rowMaxHeight)

        currentHeight = rowHeights.reduce(0, +) + max(0, CGFloat(rowHeights.count - 1)) * verticalSpacing

        // Stelle sicher, dass wir keine negative oder unendlich kleine Höhe zurückgeben
        return CGSize(width: availableWidth, height: max(0, currentHeight))
    }

    // Platziert die Unteransichten innerhalb der gegebenen Grenzen.
    func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) {
        // --- Breiten- und Subview-Prüfung HIER hinzugefügt ---
        // Nur platzieren, wenn Breite sinnvoll ist und Subviews vorhanden sind.
        guard bounds.width > 10, !subviews.isEmpty else {
            // Wenn die Breite zu klein ist, platziere nichts.
            return
        }
        // --- Ende Prüfung ---


        // Schritt 1: Bestimme, welche Subviews in welche Reihe gehören und deren Höhen
        var rowLayouts: [[(subview: LayoutSubviews.Element, size: CGSize)]] = []
        var currentRowItems: [(subview: LayoutSubviews.Element, size: CGSize)] = []
        var currentRowWidth: CGFloat = 0
        var rowHeights: [CGFloat] = []
        var currentRowMaxHeight: CGFloat = 0

        for subview in subviews {
            let subviewSize = subview.sizeThatFits(.unspecified)
            let effectiveSpacing = currentRowItems.isEmpty ? 0 : horizontalSpacing

            // Verwende bounds.width als Limit für die Zeilenbreite
            if currentRowWidth + effectiveSpacing + subviewSize.width <= bounds.width {
                currentRowWidth += effectiveSpacing + subviewSize.width
                currentRowMaxHeight = max(currentRowMaxHeight, subviewSize.height)
                currentRowItems.append((subview, subviewSize))
            } else {
                rowLayouts.append(currentRowItems)
                rowHeights.append(currentRowMaxHeight)
                currentRowItems = [(subview, subviewSize)]
                currentRowWidth = subviewSize.width
                currentRowMaxHeight = subviewSize.height
            }
        }
        if !currentRowItems.isEmpty {
            rowLayouts.append(currentRowItems)
            rowHeights.append(currentRowMaxHeight)
        }

        // Schritt 2: Platziere die Reihen zentriert
        var currentY = bounds.minY
        for rowIndex in 0..<rowLayouts.count {
            let rowContent = rowLayouts[rowIndex]
            let rowHeight = rowHeights[rowIndex]
            let currentLineWidth = rowContent.reduce(0) { $0 + $1.size.width } + max(0, CGFloat(rowContent.count - 1) * horizontalSpacing)
             // Stelle sicher, dass die Breite nicht negativ wird (kann bei extremer Verkleinerung passieren)
             let availableRowWidth = max(0, bounds.width)
            // Berechne den Startpunkt X sicher
            var currentX = bounds.minX + max(0, (availableRowWidth - currentLineWidth) / 2)

            for (subview, size) in rowContent {
                 // Stelle sicher, dass die vorgeschlagene Größe nicht negativ ist
                 let viewProposal = ProposedViewSize(width: max(0, size.width), height: max(0, size.height))
                 // Platziere nur, wenn die Position innerhalb vernünftiger Grenzen liegt
                 // (Diese Prüfung ist vielleicht übertrieben, aber sicher ist sicher)
                 if currentX.isFinite && currentY.isFinite {
                     subview.place(at: CGPoint(x: currentX, y: currentY), anchor: .topLeading, proposal: viewProposal)
                 }
                currentX += size.width + horizontalSpacing
            }
            currentY += rowHeight + verticalSpacing
        }
    }
}
