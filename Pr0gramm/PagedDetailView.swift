// PagedDetailView.swift

import SwiftUI
import os

struct PagedDetailView: View {
    let items: [Item]
    @State private var selectedIndex: Int
    @Environment(\.dismiss) var dismiss
    private static let logger = Logger(subsystem: Bundle.main.bundleIdentifier!, category: "PagedDetailView")

    @StateObject private var keyboardActionHandler = KeyboardActionHandler()

    init(items: [Item], selectedIndex: Int) {
        self.items = items
        self._selectedIndex = State(initialValue: selectedIndex)
        Self.logger.info("PagedDetailView init with selectedIndex: \(selectedIndex)")
    }

    var body: some View {
        TabView(selection: $selectedIndex) {
            ForEach(items.indices, id: \.self) { index in
                DetailViewContent(item: items[index], keyboardActionHandler: keyboardActionHandler)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                    .tag(index)
            }
        }
        .tabViewStyle(.page(indexDisplayMode: .never))
        .navigationTitle(currentItemTitle) // Verwendet die korrigierte Variable unten
        #if os(iOS)
        .navigationBarTitleDisplayMode(.inline)
        #endif
        .onChange(of: selectedIndex) { oldIndex, newIndex in
            Self.logger.info("Selected index changed from \(oldIndex) to \(newIndex)")
        }
        .onAppear {
            Self.logger.info("PagedDetailView appeared. Setting up keyboard actions.")
            keyboardActionHandler.selectNextAction = self.selectNext
            keyboardActionHandler.selectPreviousAction = self.selectPrevious
        }
        .onDisappear {
             Self.logger.info("PagedDetailView disappearing. Clearing keyboard actions.")
             keyboardActionHandler.selectNextAction = nil
             keyboardActionHandler.selectPreviousAction = nil
        }
    }

    // --- Helper (Funktionen unverändert) ---
    private func selectNext() {
        if canSelectNext { // Verwendet die korrigierte Variable unten
            Self.logger.info("Executing selectNext action.")
            selectedIndex += 1
        } else {
             Self.logger.info("Cannot selectNext (already at end).")
             #if os(iOS)
             // UIImpactFeedbackGenerator(style: .light).impactOccurred()
             #endif
        }
    }

    // --- Korrigiert: Implementierung für Computed Properties ---
    private var canSelectNext: Bool {
        return selectedIndex < items.count - 1
    }

    private func selectPrevious() {
        if canSelectPrevious { // Verwendet die korrigierte Variable unten
             Self.logger.info("Executing selectPrevious action.")
            selectedIndex -= 1
        } else {
             Self.logger.info("Cannot selectPrevious (already at start).")
             #if os(iOS)
             // UIImpactFeedbackGenerator(style: .light).impactOccurred()
             #endif
        }
    }

    // --- Korrigiert: Implementierung für Computed Properties ---
    private var canSelectPrevious: Bool {
        return selectedIndex > 0
    }

    // --- Korrigiert: Implementierung für Computed Properties ---
    private var currentItemTitle: String {
        if selectedIndex >= 0 && selectedIndex < items.count {
            return "Post \(items[selectedIndex].id)"
        } else {
            return "Detail"
        }
    }

} // Ende struct PagedDetailView


// MARK: - Preview (unverändert)
#Preview {
    let sampleItems = [
        Item(id: 1, promoted: 1001, userId: 1, down: 1, up: 10, created: Int(Date().timeIntervalSince1970 - 200), image: "img1.jpg", thumb: "t1.jpg", fullsize: "f1.jpg", preview: nil, width: 800, height: 600, audio: false, source: "http://example.com", flags: 1, user: "UserA", mark: 1),
        Item(id: 2, promoted: 1002, userId: 1, down: 2, up: 20, created: Int(Date().timeIntervalSince1970 - 100), image: "vid1.mp4", thumb: "t2.jpg", fullsize: nil, preview: nil, width: 1920, height: 1080, audio: true, source: nil, flags: 1, user: "UserB", mark: 2),
        Item(id: 3, promoted: nil, userId: 2, down: 3, up: 30, created: Int(Date().timeIntervalSince1970), image: "img2.png", thumb: "t3.png", fullsize: "f2.png", preview: nil, width: 500, height: 500, audio: false, source: nil, flags: 2, user: "UserC", mark: 0)
    ]
    NavigationStack {
        PagedDetailView(items: sampleItems, selectedIndex: 1)
            .environmentObject(AppSettings())
    }
}
