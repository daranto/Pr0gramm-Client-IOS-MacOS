// PagedDetailView.swift

import SwiftUI
import os

// InfoLoadingStatus Enum muss vorhanden sein (z.B. in CommentsSection.swift oder global)

struct PagedDetailView: View {
    let items: [Item] // Muss Identifiable sein
    @State private var selectedIndex: Int
    @Environment(\.dismiss) var dismiss
    private static let logger = Logger(subsystem: Bundle.main.bundleIdentifier!, category: "PagedDetailView")

    // Handler wird erstellt und weitergegeben
    @StateObject private var keyboardActionHandler = KeyboardActionHandler()

    @State private var loadedInfos: [Int: ItemsInfoResponse] = [:]
    @State private var infoLoadingStatus: [Int: InfoLoadingStatus] = [:]
    private let apiService = APIService()

    init(items: [Item], selectedIndex: Int) {
        self.items = items
        self._selectedIndex = State(initialValue: selectedIndex)
        Self.logger.info("PagedDetailView init with selectedIndex: \(selectedIndex)")
    }

    var body: some View {
        TabView(selection: $selectedIndex) {
            ForEach(items) { currentItem in
                // Berechne Status und Daten sicher
                let statusForItem = infoLoadingStatus[currentItem.id] ?? .idle
                let tagsForItem = loadedInfos[currentItem.id]?.tags.sorted { $0.confidence > $1.confidence } ?? []
                let commentsForItem = loadedInfos[currentItem.id]?.comments ?? []

                DetailViewContent(
                    item: currentItem,
                    // --- Handler wird an DetailViewContent übergeben ---
                    keyboardActionHandler: keyboardActionHandler,
                    tags: tagsForItem,
                    comments: commentsForItem,
                    infoLoadingStatus: statusForItem
                )
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .tag(items.firstIndex(where: { $0.id == currentItem.id }) ?? -1) // Finde Index für Tagging
                .onAppear {
                    Task { await loadInfoIfNeeded(for: currentItem) }
                    // Preload Logik
                    if let currentIndex = items.firstIndex(where: { $0.id == currentItem.id }) {
                        if currentIndex + 1 < items.count { Task { await loadInfoIfNeeded(for: items[currentIndex + 1]) } }
                        if currentIndex > 0 { Task { await loadInfoIfNeeded(for: items[currentIndex - 1]) } }
                    }
                }
            }
        }
        .tabViewStyle(.page(indexDisplayMode: .never))
        .navigationTitle(currentItemTitle)
        #if os(iOS)
        .navigationBarTitleDisplayMode(.inline)
        #endif
        .onChange(of: selectedIndex) { oldIndex, newIndex in
             // Stelle sicher, dass newIndex gültig ist
             guard newIndex >= 0 && newIndex < items.count else {
                 Self.logger.warning("onChange: Invalid newIndex \(newIndex)")
                 return
             }
             Self.logger.info("Selected index changed from \(oldIndex) to \(newIndex)")
             Task { await loadInfoIfNeeded(for: items[newIndex]) }
        }
        .onAppear {
            Self.logger.info("PagedDetailView appeared. Setting up keyboard actions.")
            // Aktionen für den Handler setzen
            keyboardActionHandler.selectNextAction = self.selectNext
            keyboardActionHandler.selectPreviousAction = self.selectPrevious
            if selectedIndex >= 0 && selectedIndex < items.count {
                 Task { await loadInfoIfNeeded(for: items[selectedIndex]) }
            }
        }
        .onDisappear {
             Self.logger.info("PagedDetailView disappearing. Clearing keyboard actions.")
             keyboardActionHandler.selectNextAction = nil
             keyboardActionHandler.selectPreviousAction = nil
        }
        // --- ENTFERNT: Kein .background oder .overlay mit KeyCommandView ---
    }

    // --- loadInfoIfNeeded ---
    private func loadInfoIfNeeded(for item: Item) async {
        let itemId = item.id
        guard infoLoadingStatus[itemId] == nil || infoLoadingStatus[itemId] == .idle else { return }
        Self.logger.debug("Starting info load for item \(itemId)...")
        await MainActor.run { infoLoadingStatus[itemId] = .loading }
        do {
            let infoResponse = try await apiService.fetchItemInfo(itemId: itemId)
            await MainActor.run {
                loadedInfos[itemId] = infoResponse
                infoLoadingStatus[itemId] = .loaded
                Self.logger.debug("Successfully loaded info for item \(itemId). Tags: \(infoResponse.tags.count), Comments: \(infoResponse.comments.count)")
            }
        } catch {
            Self.logger.error("Failed to load info for item \(itemId): \(error.localizedDescription)")
            await MainActor.run {
                infoLoadingStatus[itemId] = .error(error.localizedDescription)
            }
        }
    }

    // --- Helper für Navigation ---
    private func selectNext() {
        if canSelectNext {
            Self.logger.info("Executing selectNext action (triggered by Handler).")
            selectedIndex += 1
        } else {
             Self.logger.info("Cannot selectNext (already at end).")
        }
    }

    private var canSelectNext: Bool {
        return selectedIndex < items.count - 1
    }

    private func selectPrevious() {
        if canSelectPrevious {
             Self.logger.info("Executing selectPrevious action (triggered by Handler).")
            selectedIndex -= 1
        } else {
             Self.logger.info("Cannot selectPrevious (already at start).")
        }
    }

    private var canSelectPrevious: Bool {
        return selectedIndex > 0
    }

    // --- currentItemTitle ---
    private var currentItemTitle: String {
        guard selectedIndex >= 0 && selectedIndex < items.count else { return "Detail" }
        let currentItem = items[selectedIndex]
        let status = infoLoadingStatus[currentItem.id] ?? .idle
        switch status {
        case .loaded:
            let topTag = loadedInfos[currentItem.id]?.tags.max(by: { $0.confidence < $1.confidence })?.tag
            if let tag = topTag, !tag.isEmpty { return tag }
            else { return "Post \(currentItem.id)" }
        case .loading: return "Lade Infos..."
        case .error: return "Fehler"
        case .idle: return "Post \(currentItem.id)"
        }
    }

} // Ende struct PagedDetailView


// MARK: - Preview
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
