import SwiftUI

// Die Hauptansicht der App, die das Raster der Posts anzeigt.
struct ContentView: View {

    // MARK: - State Properties

    // @State-Variablen speichern den Zustand der View. Änderungen daran
    // führen automatisch zu einer Neuzeichnung der betroffenen Teile der UI.

    // Speichert die Liste der geladenen Items (Posts). Beginnt leer.
    @State private var items: [Item] = []
    // Speichert eine eventuelle Fehlermeldung als String. nil bedeutet kein Fehler.
    @State private var errorMessage: String?
    // Zeigt an, ob gerade Daten geladen werden (für die Ladeanzeige).
    @State private var isLoading = false

    // MARK: - Properties

    // Eine Instanz unseres API-Service zum Abrufen der Daten.
    // 'private' bedeutet, dass nur innerhalb dieser Struktur darauf zugegriffen werden kann.
    // 'let' bedeutet, dass die Instanz selbst nicht geändert wird (obwohl ihr Inhalt sich ändern kann).
    private let apiService = APIService()

    // Definiert das Layout der Spalten für das LazyVGrid.
    // .adaptive(minimum: 100) erstellt so viele Spalten wie möglich,
    // wobei jede mindestens 100 Punkte breit ist. Ideal für verschiedene Bildschirmgrößen.
    // 'spacing' definiert den horizontalen Abstand zwischen den Zellen.
    let columns: [GridItem] = [
        GridItem(.adaptive(minimum: 100), spacing: 3) // Passe 'minimum' und 'spacing' nach Geschmack an.
    ]

    // MARK: - Body

    // Der 'body' definiert die eigentliche Struktur und das Aussehen der View.
    var body: some View {
        // NavigationStack ermöglicht die Navigation zu anderen Ansichten (wie DetailView).
        // Es ist der moderne Weg für Navigation in SwiftUI.
        NavigationStack {
            // ScrollView ermöglicht das vertikale Scrollen des Inhalts.
            ScrollView {
                // LazyVGrid ordnet die Elemente in einem Raster an.
                // 'Lazy' bedeutet, dass Zellen erst erstellt werden, wenn sie sichtbar werden.
                // 'columns' definiert das Spaltenlayout (siehe oben).
                // 'spacing' definiert den vertikalen Abstand zwischen den Zeilen.
                LazyVGrid(columns: columns, spacing: 3) {
                    // ForEach iteriert durch das 'items'-Array.
                    // 'Item' muss 'Identifiable' sein (haben wir in Item.swift sichergestellt).
                    ForEach(items) { item in
                        // NavigationLink macht die Zelle klickbar und navigiert
                        // zum Ziel, das im .navigationDestination definiert ist.
                        // 'value: item' übergibt das angeklickte Item an das Ziel.
                        NavigationLink(value: item) {
                            // Inhalt jeder Zelle im Grid:
                            AsyncImage(url: item.thumbnailUrl) { phase in
                                // Behandelt die verschiedenen Ladezustände des Bildes.
                                switch phase {
                                case .success(let image):
                                    // Erfolgreich geladen: Zeige das Bild an.
                                    image
                                        .resizable() // Bildgröße anpassbar machen.
                                        // Füllt den verfügbaren Raum, behält Seitenverhältnis, schneidet Überstand ab.
                                        .aspectRatio(contentMode: .fill)
                                case .failure:
                                    // Fehler beim Laden: Zeige einen Platzhalter mit Fehler-Icon.
                                    Rectangle()
                                        .fill(Color.gray.opacity(0.3))
                                        .overlay(Image(systemName: "exclamationmark.triangle.fill").foregroundColor(.gray))
                                case .empty:
                                    // Noch nicht geladen: Zeige einen Platzhalter mit Ladeanzeige.
                                    Rectangle()
                                        .fill(Color.gray.opacity(0.1))
                                        .overlay(ProgressView())
                                @unknown default:
                                    // Für zukünftige Zustände.
                                    EmptyView()
                                }
                            }
                            // Stellt sicher, dass die Zelle (der Container des Bildes)
                            // quadratisch ist (1.0 = Verhältnis 1:1).
                            .aspectRatio(1.0, contentMode: .fit)
                            // Rundet die Ecken der Zelle ab.
                            .cornerRadius(5)
                        }
                        // Verhindert, dass der NavigationLink auf macOS/iPadOS
                        // wie ein Standard-Button aussieht oder einen Pfeil anzeigt.
                        .buttonStyle(.plain)
                    } // Ende ForEach
                } // Ende LazyVGrid
                // Fügt einen kleinen horizontalen Abstand zum Rand der ScrollView hinzu.
                .padding(.horizontal, 5)
                // Fügt etwas Abstand am unteren Rand hinzu, falls nötig.
                .padding(.bottom)

            } // Ende ScrollView
            // Setzt den Haupttitel in der Navigationsleiste.
            .navigationTitle("pr0gramm Feed") // Passe den Titel an, wie du möchtest.
            // .task wird ausgeführt, wenn die View erscheint.
            // Ideal zum asynchronen Laden von Daten.
            .task {
                // Lädt die Daten nur, wenn die Liste aktuell leer ist.
                // Verhindert Neuladen bei jeder Rückkehr von der DetailView.
                // (Kann später durch Pull-to-Refresh etc. verbessert werden).
                if items.isEmpty {
                    await loadItems()
                }
            }
            // .overlay legt eine View über die bestehende View.
            // Wird hier genutzt, um eine Ladeanzeige anzuzeigen, wenn isLoading true ist.
            .overlay {
                if isLoading {
                    // Zeigt einen halbtransparenten Hintergrund und eine Ladeanzeige.
                    ZStack {
                         Color.black.opacity(0.1) // Optional: Hintergrund dimmen
                             .ignoresSafeArea()
                         ProgressView("Lade Items...")
                             .padding()
                             .background(Material.regular) // Moderner Blur-Effekt
                             .cornerRadius(10)
                    }
                }
            }
            // Zeigt ein Alert-Fenster an, wenn 'errorMessage' nicht nil ist.
            .alert("Fehler", isPresented: .constant(errorMessage != nil), actions: {
                // Fügt einen OK-Button hinzu, der die Fehlermeldung zurücksetzt.
                Button("OK") {
                    errorMessage = nil
                }
            }) {
                // Der Text im Alert-Fenster.
                Text(errorMessage ?? "Ein unbekannter Fehler ist aufgetreten.")
            }
            // Definiert, welche View angezeigt wird, wenn ein NavigationLink
            // mit einem Wert vom Typ 'Item' aktiviert wird.
            // Definiert, welche View angezeigt wird, wenn ein NavigationLink
                        // mit einem Wert vom Typ 'Item' aktiviert wird.
                        .navigationDestination(for: Item.self) { tappedItem in
                            // Finde den Index des angeklickten Items in unserer Liste
                            if let index = items.firstIndex(where: { $0.id == tappedItem.id }) {
                                // Erzeuge die PagedDetailView und übergebe die Liste und den Index
                                PagedDetailView(items: items, selectedIndex: index)
                                    // Kein plattformspezifischer Modifier mehr hier nötig,
                                    // da dies jetzt in PagedDetailView gehandhabt wird.
                            } else {
                                // Fallback, falls das Item aus irgendeinem Grund nicht gefunden wird
                                // (sollte nicht passieren, wenn 'items' die Quelle ist)
                                Text("Fehler: Item nicht in der Liste gefunden.")
                            }
                        } // Ende navigationDestination

        } // Ende NavigationStack
        // Auf iPad und Mac kann eine Spaltennavigation sinnvoll sein.
        // Für den Anfang ist die einfache NavigationStack aber ausreichend.
        // .navigationViewStyle(.stack) // Ggf. für Konsistenz auf iPad
    }

    // MARK: - Functions

    // Funktion zum Laden der Items von der API.
    // 'async' bedeutet, dass sie asynchrone Aufrufe (wie apiService.fetchItems) enthalten kann.
    func loadItems() async {
        // Verhindert mehrfaches Laden, wenn bereits ein Ladevorgang läuft.
        guard !isLoading else { return }

        print("Lade Items...") // Log-Ausgabe für Debugging
        isLoading = true // Ladeanzeige aktivieren
        errorMessage = nil // Vorherigen Fehler zurücksetzen

        // do-catch-Block zum Abfangen von Fehlern während des API-Aufrufs.
        do {
            // Ruft die fetchItems-Funktion im APIService auf und wartet ('await') auf das Ergebnis.
            let fetchedItems = try await apiService.fetchItems()

            // WICHTIG: UI-Updates müssen immer auf dem Main-Thread stattfinden.
            // MainActor.run stellt sicher, dass der Code im Block auf dem Main Thread ausgeführt wird.
            await MainActor.run {
                self.items = fetchedItems // Aktualisiert die @State-Variable, UI wird neu gezeichnet.
                self.isLoading = false // Ladeanzeige deaktivieren
                print("Items erfolgreich geladen: \(fetchedItems.count) Stück")
            }
        } catch {
            // Fehler beim API-Aufruf abgefangen.
            await MainActor.run {
                self.errorMessage = "Fehler beim Laden: \(error.localizedDescription)"
                self.isLoading = false // Ladeanzeige deaktivieren
                print("Fehler beim Laden der Items: \(error)") // Detaillierte Fehlerausgabe im Log
            }
        }
    }
}

// MARK: - Preview

#Preview {
    ContentView()
    // Hier könnten EnvironmentObjects etc. für die Vorschau hinzugefügt werden, falls nötig.
}
