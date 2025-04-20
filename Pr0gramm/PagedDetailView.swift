// PagedDetailView.swift

import SwiftUI

// Diese View zeigt die Detailansicht eines Items an und erlaubt das Wechseln
// zwischen Items per Swipe (iOS) oder Pfeiltasten (macOS) mittels einer TabView.
struct PagedDetailView: View {
    // Die Liste aller Items, durch die navigiert werden kann.
    let items: [Item]
    // Der Index des aktuell angezeigten Items in der `items`-Liste.
    @State private var selectedIndex: Int

    // Zugriff auf die dismiss-Action der Environment, um programmatisch zurückzugehen.
    @Environment(\.dismiss) var dismiss

    // Initialisierer, um die Item-Liste und den Startindex von außen zu erhalten.
    init(items: [Item], selectedIndex: Int) {
        self.items = items
        self._selectedIndex = State(initialValue: selectedIndex)
    }

    // Definiert das Layout und Verhalten der View.
    var body: some View {
        // TabView dient als Container für die einzelnen Item-Seiten.
        // Die 'selection'-Bindung sorgt für die Synchronisation mit 'selectedIndex'.
        TabView(selection: $selectedIndex) {
            // Erzeugt für jedes Item eine Seite. Iteration über Indizes für den .tag().
            ForEach(items.indices, id: \.self) { index in
                // Zeigt den Inhalt des Items mithilfe der DetailViewContent an.
                DetailViewContent(item: items[index])
                    // Stellt sicher, dass der Inhalt den verfügbaren Platz ausfüllt.
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                    // Weist jeder Seite ihren Index als Tag zu (wichtig für selection).
                    .tag(index)
            } // Ende ForEach
        } // Ende TabView

        // --- Platformspezifische und allgemeine Modifier ---

        #if os(iOS)
        // Nur auf iOS: Paging-Stil für horizontales Swipen aktivieren.
        .tabViewStyle(.page(indexDisplayMode: .never))
        // Nur auf iOS: Kleinen Inline-Titel in der Navigationsleiste verwenden.
        .navigationBarTitleDisplayMode(.inline)
        #endif

        // Setzt den Titel der Navigationsleiste dynamisch.
        .navigationTitle(currentItemTitle)

        // Fügt die unsichtbare View für die Pfeiltasten-Navigation auf macOS hinzu.
        .background(macOSKeyboardNavigaion(selectedIndex: $selectedIndex, maxIndex: items.count - 1))

        // Weist die TabView an, den verfügbaren Platz zu füllen.
        .frame(maxWidth: .infinity, maxHeight: .infinity)

        // --- Expliziter Zurück-Button nur für macOS ---
        #if os(macOS)
        .toolbar {
            // Fügt ein Toolbar-Item am Anfang (links) der Toolbar hinzu.
            ToolbarItem(placement: .navigation) {
                // Button, der die dismiss-Action aufruft, um zurückzugehen.
                Button {
                    dismiss()
                } label: {
                    // Standard-Label für einen Zurück-Button.
                    Label("Zurück", systemImage: "chevron.backward")
                }
                // Optional: Tastaturkürzel (Cmd+[ ist aber oft Standard)
                // .keyboardShortcut("[", modifiers: .command)
            }
        }
        #endif // --- Ende macOS Toolbar ---
    } // Ende body

    // Berechnete Eigenschaft für den dynamischen Navigationstitel.
    private var currentItemTitle: String {
        if selectedIndex >= 0 && selectedIndex < items.count {
            // Zeigt die ID des aktuellen Posts im Titel an.
            return "Post \(items[selectedIndex].id)"
        } else {
            // Fallback-Titel.
            return "Detail"
        }
    }
} // Ende struct PagedDetailView

// MARK: - macOS Keyboard Navigation Helper

// Kleine Hilfs-View mit unsichtbaren Buttons für Pfeiltasten-Navigation auf macOS.
struct macOSKeyboardNavigaion: View {
    // Bindung zum Index der Hauptview.
    @Binding var selectedIndex: Int
    // Maximal erlaubter Index.
    let maxIndex: Int

    var body: some View {
        HStack {
            // Button für Linkspfeil (Zurück).
            Button("Previous") { if selectedIndex > 0 { selectedIndex -= 1 } }
                .keyboardShortcut(.leftArrow, modifiers: []) // Tastenkürzel
                .opacity(0).frame(width: 0, height: 0) // Unsichtbar machen

            // Button für Rechtspfeil (Weiter).
            Button("Next") { if selectedIndex < maxIndex { selectedIndex += 1 } }
                .keyboardShortcut(.rightArrow, modifiers: []) // Tastenkürzel
                .opacity(0).frame(width: 0, height: 0) // Unsichtbar machen
        }
    }
}

// MARK: - Preview

#Preview {
    // Erzeugt Beispiel-Daten für die Vorschau.
    let sampleItems = [
        Item(id: 1, image: "img1.jpg", thumb: "t1.jpg", width: 800, height: 600, up: 10, down: 1),
        Item(id: 2, image: "vid1.mp4", thumb: "t2.jpg", width: 1920, height: 1080, up: 20, down: 2),
        Item(id: 3, image: "img2.png", thumb: "t3.png", width: 500, height: 500, up: 30, down: 3),
    ]

    // Zeigt die Vorschau innerhalb einer NavigationStack für Kontext.
    NavigationStack {
        PagedDetailView(items: sampleItems, selectedIndex: 1)
            // Stellt sicher, dass die Preview auch auf die Einstellungen zugreifen kann,
            // falls PagedDetailView oder DetailViewContent dies benötigen würden.
            .environmentObject(AppSettings())
    }
}
