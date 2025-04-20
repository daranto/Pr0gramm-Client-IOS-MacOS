// FeedView.swift

import SwiftUI

// Struktur für die Anzeige des Thumbnails (ausgelagert wegen Compiler-Komplexität)
struct FeedItemThumbnail: View {
    let item: Item // Das Item, dessen Thumbnail angezeigt werden soll

    var body: some View {
        AsyncImage(url: item.thumbnailUrl) { phase in
            switch phase {
            case .success(let image):
                image
                    .resizable()
                    .aspectRatio(contentMode: .fill) // Füllt den quadratischen Rahmen
            case .failure:
                // Zeigt ein graues Rechteck mit Fehler-Icon an
                Rectangle()
                    .fill(Material.ultraThin) // Subtiler Hintergrund
                    .overlay(
                        Image(systemName: "exclamationmark.triangle.fill")
                            .foregroundColor(.secondary)
                    )
            default: // .empty & @unknown
                // Zeigt ein Rechteck mit Ladeanzeige
                Rectangle()
                    .fill(Material.ultraThin) // Subtiler Hintergrund
                    .overlay(ProgressView())
            }
        }
        // Sorgt dafür, dass die Zelle quadratisch ist
        .aspectRatio(1.0, contentMode: .fit)
        // Rundet die Ecken ab
        .cornerRadius(5)
        .clipped() // Verhindert Überzeichnen
    }
}


// Zeigt den Haupt-Feed-Grid an.
struct FeedView: View {

    @EnvironmentObject var settings: AppSettings
    @State private var items: [Item] = []
    @State private var errorMessage: String?
    @State private var isLoading = false
    @State private var showingFilterSheet = false

    private let apiService = APIService()
    let columns: [GridItem] = [ GridItem(.adaptive(minimum: 100), spacing: 3) ]

    var body: some View {
        NavigationStack {
            ScrollView {
                LazyVGrid(columns: columns, spacing: 3) {
                    ForEach(items) { item in
                        NavigationLink(value: item) {
                            FeedItemThumbnail(item: item)
                        }
                        .buttonStyle(.plain)
                    }
                }
                .padding(.horizontal, 5)
                .padding(.bottom)
            } // Ende ScrollView
            .navigationTitle(settings.feedType.displayName) // Dynamischer Titel
            // --- Toolbar mit Filter-Button ---
            .toolbar {
                // HIER DIE KORREKTUR: Verwende eine plattformübergreifende Platzierung
                ToolbarItem(placement: .primaryAction) { // <-- Geändert von .navigationBarTrailing
                    Button {
                        showingFilterSheet = true // Öffnet das Sheet
                    } label: {
                        Label("Filter", systemImage: "line.3.horizontal.decrease.circle")
                    }
                }
            } // Ende Toolbar
            // Sheet für die Filter-Ansicht
            .sheet(isPresented: $showingFilterSheet) {
                 FilterView().environmentObject(settings)
            }
            // Ladeanzeige als Overlay
            .loadingOverlay(isLoading: isLoading)
            // Fehleranzeige als Alert
            .alert("Fehler", isPresented: .constant(errorMessage != nil), actions: {
                Button("OK") { errorMessage = nil }
            }) {
                Text(errorMessage ?? "Ein unbekannter Fehler ist aufgetreten.")
            }
            // Navigation zur Detailansicht
            .navigationDestination(for: Item.self) { destinationItem in
                if let index = items.firstIndex(where: { $0.id == destinationItem.id }) {
                     PagedDetailView(items: items, selectedIndex: index)
                 } else {
                     Text("Fehler: Item nicht gefunden.")
                 }
            }
            // Reagieren auf Einstellungsänderungen
            .onChange(of: settings.feedType, initial: false) { _, _ in Task { await loadItems() } }
            .onChange(of: settings.showSFW, initial: false) { _, _ in Task { await loadItems() } }
            .onChange(of: settings.showNSFW, initial: false) { _, _ in Task { await loadItems() } }
            .onChange(of: settings.showNSFL, initial: false) { _, _ in Task { await loadItems() } }
            .onChange(of: settings.showPOL, initial: false) { _, _ in Task { await loadItems() } }
            // Initiales Laden der Daten
            .task {
                if items.isEmpty { await loadItems() }
            }
        } // Ende NavigationStack
    }

    // Funktion zum Laden der Items von der API (unverändert)
    func loadItems() async {
        guard !isLoading else { return }
        isLoading = true
        errorMessage = nil
        await MainActor.run { items = [] }
        print("Loading items with flags: \(settings.apiFlags), promoted: \(settings.apiPromoted)")

        do {
            let fetchedItems = try await apiService.fetchItems(
                flags: settings.apiFlags,
                promoted: settings.apiPromoted
            )
            await MainActor.run {
                self.items = fetchedItems
                self.isLoading = false
                print("Items loaded: \(fetchedItems.count)")
            }
        } catch {
            await MainActor.run {
                self.errorMessage = "Fehler beim Laden: \(error.localizedDescription)"
                self.isLoading = false
                print("Error loading items: \(error)")
            }
        }
    }
}

// MARK: - View Extension for Loading Overlay (unverändert)
extension View {
    func loadingOverlay(isLoading: Bool) -> some View {
        self.overlay {
             if isLoading {
                 ZStack {
                     ProgressView("Lade...")
                         .padding()
                         .background(Material.regular)
                         .cornerRadius(10)
                 }
             }
        }
    }
}

// MARK: - Preview
#Preview {
    FeedView()
        .environmentObject(AppSettings()) // Benötigt für Vorschau
}
