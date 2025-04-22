// PagedDetailView.swift

import SwiftUI
import os

// --- Enum für TagLoadingStatus (unverändert) ---
enum TagLoadingStatus: Equatable {
    case idle
    case loading
    case loaded
    case error(String)
}

struct PagedDetailView: View {
    let items: [Item]
    @State private var selectedIndex: Int
    @Environment(\.dismiss) var dismiss
    private static let logger = Logger(subsystem: Bundle.main.bundleIdentifier!, category: "PagedDetailView")

    // KeyboardActionHandler wird für die Weitergabe an DetailViewContent benötigt
    @StateObject private var keyboardActionHandler = KeyboardActionHandler()

    @State private var loadedTags: [Int: [ItemTag]] = [:]
    @State private var tagLoadingStatus: [Int: TagLoadingStatus] = [:]
    private let apiService = APIService()

    init(items: [Item], selectedIndex: Int) {
        self.items = items
        self._selectedIndex = State(initialValue: selectedIndex)
        Self.logger.info("PagedDetailView init with selectedIndex: \(selectedIndex)")
    }

    var body: some View {
        TabView(selection: $selectedIndex) {
            ForEach(items.indices, id: \.self) { index in
                let currentItem = items[index]
                let tagsForItem = loadedTags[currentItem.id] ?? []
                let statusForItem = tagLoadingStatus[currentItem.id] ?? .idle

                DetailViewContent(
                    item: currentItem,
                    keyboardActionHandler: keyboardActionHandler, // Wird weitergereicht
                    tags: tagsForItem,
                    tagLoadingStatus: statusForItem
                )
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .tag(index)
                .onAppear {
                    Task { await loadTagsIfNeeded(for: currentItem) }
                    if index + 1 < items.count { Task { await loadTagsIfNeeded(for: items[index + 1]) } }
                    if index > 0 { Task { await loadTagsIfNeeded(for: items[index - 1]) } }
                }
            }
        }
        .tabViewStyle(.page(indexDisplayMode: .never))
        .navigationTitle(currentItemTitle)
        #if os(iOS)
        .navigationBarTitleDisplayMode(.inline)
        #endif
        .onChange(of: selectedIndex) { oldIndex, newIndex in
            Self.logger.info("Selected index changed from \(oldIndex) to \(newIndex)")
            if newIndex >= 0 && newIndex < items.count {
                Task { await loadTagsIfNeeded(for: items[newIndex]) }
            }
        }
        .onAppear {
            Self.logger.info("PagedDetailView appeared. Setting up keyboard actions.")
            keyboardActionHandler.selectNextAction = self.selectNext
            keyboardActionHandler.selectPreviousAction = self.selectPrevious
            if selectedIndex >= 0 && selectedIndex < items.count {
                 Task { await loadTagsIfNeeded(for: items[selectedIndex]) }
            }
        }
        .onDisappear {
             Self.logger.info("PagedDetailView disappearing. Clearing keyboard actions.")
             keyboardActionHandler.selectNextAction = nil
             keyboardActionHandler.selectPreviousAction = nil
        }
        // --- ENTFERNT: Hintergrund-View für Tastatur nicht mehr nötig ---
        // .background(KeyCommandView(handler: keyboardActionHandler))
    }

    // --- loadTagsIfNeeded (unverändert) ---
    private func loadTagsIfNeeded(for item: Item) async {
        let itemId = item.id
        guard tagLoadingStatus[itemId] == nil || tagLoadingStatus[itemId] == .idle else { return }
        Self.logger.debug("Starting tag load for item \(itemId)...")
        await MainActor.run { tagLoadingStatus[itemId] = .loading }
        do {
            let infoResponse = try await apiService.fetchItemInfo(itemId: itemId)
            let sortedTags = infoResponse.tags.sorted { $0.confidence > $1.confidence }
            await MainActor.run {
                loadedTags[itemId] = sortedTags
                tagLoadingStatus[itemId] = .loaded
                Self.logger.debug("Successfully loaded \(sortedTags.count) tags for item \(itemId).")
            }
        } catch {
            Self.logger.error("Failed to load tags for item \(itemId): \(error.localizedDescription)")
            await MainActor.run {
                tagLoadingStatus[itemId] = .error(error.localizedDescription)
            }
        }
    }

    // --- Helper für Navigation (unverändert) ---
    private func selectNext() { if canSelectNext { selectedIndex += 1 } }
    private var canSelectNext: Bool { selectedIndex < items.count - 1 }
    private func selectPrevious() { if canSelectPrevious { selectedIndex -= 1 } }
    private var canSelectPrevious: Bool { selectedIndex > 0 }

    // --- currentItemTitle (unverändert) ---
    private var currentItemTitle: String {
        guard selectedIndex >= 0 && selectedIndex < items.count else { return "Detail" }
        let currentItem = items[selectedIndex]
        let status = tagLoadingStatus[currentItem.id] ?? .idle
        switch status {
        case .loaded:
            if let topTag = loadedTags[currentItem.id]?.first?.tag, !topTag.isEmpty {
                return topTag
            } else {
                return "Post \(currentItem.id)"
            }
        case .loading:
            return "Lade Tags..."
        case .error:
            return "Fehler"
        case .idle:
            return "Post \(currentItem.id)"
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
    return NavigationStack {
        PagedDetailView(items: sampleItems, selectedIndex: 1)
            .environmentObject(AppSettings())
    }
}
