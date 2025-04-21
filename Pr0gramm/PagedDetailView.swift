// PagedDetailView.swift

import SwiftUI

// Diese View zeigt die Detailansicht eines Items an und erlaubt das Wechseln
// zwischen Items per Swipe (iOS) oder Pfeiltasten (macOS) mittels einer TabView.
struct PagedDetailView: View {
    let items: [Item]
    @State private var selectedIndex: Int
    @Environment(\.dismiss) var dismiss

    init(items: [Item], selectedIndex: Int) {
        self.items = items
        self._selectedIndex = State(initialValue: selectedIndex)
    }

    var body: some View {
        TabView(selection: $selectedIndex) {
            ForEach(items.indices, id: \.self) { index in
                // Hier wird DetailViewContent verwendet
                DetailViewContent(item: items[index])
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                    .tag(index)
            }
        }
        #if os(iOS)
        .tabViewStyle(.page(indexDisplayMode: .never))
        .navigationBarTitleDisplayMode(.inline)
        #endif
        .navigationTitle(currentItemTitle)
        // macOSKeyboardNavigaion wird hier verwendet
        .background(macOSKeyboardNavigaion(selectedIndex: $selectedIndex, maxIndex: items.count - 1))
    }

    private var currentItemTitle: String {
        if selectedIndex >= 0 && selectedIndex < items.count {
            return "Post \(items[selectedIndex].id)"
        } else {
            return "Detail"
        }
    }
} // Ende struct PagedDetailView

// MARK: - macOS Keyboard Navigation Helper (Hier definiert)
struct macOSKeyboardNavigaion: View {
    @Binding var selectedIndex: Int
    let maxIndex: Int

    var body: some View {
        HStack {
            Button("Previous") { if selectedIndex > 0 { selectedIndex -= 1 } }
                .keyboardShortcut(.leftArrow, modifiers: [])
                .opacity(0).frame(width: 0, height: 0)
            Button("Next") { if selectedIndex < maxIndex { selectedIndex += 1 } }
                .keyboardShortcut(.rightArrow, modifiers: [])
                .opacity(0).frame(width: 0, height: 0)
        }
    }
}

// MARK: - Preview (KORRIGIERTER Initializer)
#Preview {
    // Beispiel-Daten mit allen Feldern aus Item.swift
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
