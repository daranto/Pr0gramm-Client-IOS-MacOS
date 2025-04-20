import SwiftUI
import AVKit // Benötigt für VideoPlayer und AVPlayer

// Stellt die Detailansicht für einen einzelnen Post dar.
// Zeigt entweder ein Bild oder ein Video an.
struct DetailViewContent: View {
    // Das anzuzeigende Item-Objekt, wird von der ContentView übergeben.
    let item: Item

    // State-Variable für den AVPlayer. @State sorgt dafür, dass die View
    // den Player über Neuzeichnungen hinweg behält und auf Änderungen reagieren kann.
    // Er ist optional (?), da wir ihn nur für Videos brauchen.
    @State private var player: AVPlayer? = nil

    var body: some View {
        // ScrollView erlaubt es, den Inhalt zu scrollen, falls er
        // (insbesondere das Bild/Video) größer als der Bildschirm ist.
        ScrollView {
            // VStack ordnet die Elemente (Bild/Video und Text) vertikal an.
            VStack {
                // --- Bedingte Anzeige: Video oder Bild ---
                if item.isVideo {
                    // Fall 1: Es ist ein Video

                    // Wir versuchen sicherzustellen, dass die URL gültig ist.
                    if let url = item.imageUrl {
                        // Erzeuge den VideoPlayer. Er benötigt eine AVPlayer-Instanz.
                        // Wir verwenden die @State-Variable 'player'.
                        VideoPlayer(player: player)
                            // Passt die Größe des Videos an den verfügbaren Platz an,
                            // behält aber das Seitenverhältnis bei.
                            .aspectRatio(contentMode: .fit)
                            // .onAppear wird ausgeführt, wenn die View auf dem Bildschirm erscheint.
                            .onAppear {
                                // Erzeuge oder aktualisiere den AVPlayer.
                                // Die Prüfung stellt sicher, dass wir nicht unnötig einen
                                // neuen Player erstellen, wenn die View nur neu gezeichnet wird.
                                if player == nil || player?.currentItem?.asset != AVURLAsset(url: url) {
                                     player = AVPlayer(url: url)
                                     // Optional: Wenn das Video automatisch starten soll:
                                     // player?.play()
                                }
                            }
                            // .onDisappear wird ausgeführt, wenn die View vom Bildschirm verschwindet.
                            .onDisappear {
                                // Pausiere das Video, um Ressourcen zu sparen und zu verhindern,
                                // dass es im Hintergrund weiterläuft.
                                player?.pause()
                                // Optional: Player auf nil setzen, um Speicher freizugeben
                                // player = nil
                            }
                            // Gib dem Player eine Mindesthöhe, damit der Bereich nicht
                            // leer ist, bevor das Video geladen ist.
                            .frame(minHeight: 200) // Passe die Höhe nach Bedarf an

                    } else {
                        // Fallback, wenn die Video-URL aus irgendeinem Grund ungültig ist.
                        Text("Video konnte nicht geladen werden (Ungültige URL).")
                            .foregroundColor(.red)
                            .frame(minHeight: 200, alignment: .center)
                            .padding()
                    }
                } else {
                    // Fall 2: Es ist ein Bild

                    // AsyncImage lädt Bilder asynchron von einer URL.
                    AsyncImage(url: item.imageUrl) { phase in
                        // 'phase' repräsentiert den Ladezustand des Bildes.
                        switch phase {
                        case .empty:
                            // Zustand: Das Laden hat noch nicht begonnen.
                            // Zeige eine Ladeanzeige.
                            ProgressView()
                                // Gib dem Platzhalter eine Mindesthöhe.
                                .frame(minHeight: 200)
                        case .success(let image):
                            // Zustand: Das Bild wurde erfolgreich geladen.
                            image
                                .resizable() // Erlaube Größenänderung des Bildes.
                                .scaledToFit() // Skaliere das Bild, sodass es passt, Seitenverhältnis bleibt erhalten.
                        case .failure:
                            // Zustand: Das Laden ist fehlgeschlagen.
                            // Zeige eine Fehlermeldung.
                            VStack {
                                Image(systemName: "photo") // Symbol
                                    .font(.largeTitle)
                                Text("Bild konnte nicht geladen werden.")
                                    .foregroundColor(.red)
                            }
                            .frame(minHeight: 200, alignment: .center)
                            .padding()
                        @unknown default:
                            // Zukünftiger, unbekannter Zustand.
                            EmptyView()
                                .frame(minHeight: 200)
                        }
                    }
                }
                // --- Ende der bedingten Anzeige ---

                // Zeigt zusätzliche Informationen unter dem Bild/Video an.
                HStack {
                    Text("ID: \(item.id)")
                        .font(.caption)
                    Spacer() // Schiebt die Elemente auseinander
                    Text("⬆️ \(item.up)")
                        .font(.caption)
                    Text("⬇️ \(item.down)")
                        .font(.caption)
                }
                .padding(.horizontal) // Abstand links/rechts
                .padding(.bottom) // Abstand nach unten

                // Platzhalter für zukünftige Elemente (z.B. Kommentare)
                // Text("Kommentare...")
                //    .padding()
            }
        }
        // Setzt den Titel der Navigationsleiste für diese Ansicht.
        .navigationTitle("Post \(item.id)")
        // Hinweis: .navigationBarTitleDisplayMode(.inline) wird üblicherweise
        // im .navigationDestination der aufrufenden View (ContentView) gesetzt,
        // um plattformspezifischen Code dort zu bündeln.
    }
}

// MARK: - Preview

#Preview {
    // Erstelle Beispiel-Items für die Vorschau in Xcode.
    // Es ist nützlich, Beispiele für Bild und Video zu haben.

    let sampleImageItem = Item(
        id: 12345,
        image: "example.jpg", // Fiktiver Dateiname
        thumb: "example_thumb.jpg",
        width: 800,
        height: 600,
        up: 250,
        down: 15
        // Stelle sicher, dass alle benötigten Felder von Item hier initialisiert werden.
    )

    let sampleVideoItem = Item(
        id: 67890,
        image: "example.mp4", // Wichtig: Video-Endung für die isVideo-Logik
        thumb: "example_vid_thumb.jpg",
        width: 1920,
        height: 1080,
        up: 500,
        down: 5
    )

    // Zeige die Vorschau innerhalb einer NavigationStack, damit der Titel sichtbar ist.
    NavigationStack {
        // Wähle eines der Beispiel-Items für die Vorschau aus:
        // DetailView(item: sampleImageItem)
         DetailView(item: sampleVideoItem) // Oder dieses für die Video-Vorschau
    }
    // Optional: .environmentObject oder andere Modifikatoren hier hinzufügen,
    // falls deine View Abhängigkeiten hat.
}
