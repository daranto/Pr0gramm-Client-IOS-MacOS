// DetailViewContent.swift

import SwiftUI
import AVKit // Für AVPlayer, VideoPlayer
import Combine // Für KVO (NSKeyValueObservation)

struct DetailViewContent: View {
    let item: Item

    // Zugriff auf die globalen App-Einstellungen.
    @EnvironmentObject var settings: AppSettings

    // State für den Player wie gehabt.
    @State private var player: AVPlayer? = nil
    // State zum Speichern des KVO-Beobachters für die isMuted-Eigenschaft.
    @State private var muteObserver: NSKeyValueObservation? = nil

    var body: some View {
        VStack(spacing: 0) {
            Color.clear
                .aspectRatio(guessAspectRatio(), contentMode: .fit)
                .overlay(mediaView()) // mediaView wird jetzt komplexer
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .clipped()

            // Metadatenbereich (unverändert)
            HStack {
                Text("ID: \(item.id)").font(.caption).lineLimit(1)
                Spacer()
                Text("⬆️ \(item.up)").font(.caption)
                Text("⬇️ \(item.down)").font(.caption)
            }
            .padding(.vertical, 8)
            .padding(.horizontal)
            .frame(maxWidth: .infinity)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        // WICHTIG: KVO Observer entfernen, wenn die View verschwindet!
        .onDisappear {
            cleanupPlayerAndObserver()
        }
    }

    // MARK: - Media View & Player Logic

    @ViewBuilder
    private func mediaView() -> some View {
        if item.isVideo {
            if let url = item.imageUrl {
                // VideoPlayer verwendet die @State 'player'-Variable.
                VideoPlayer(player: player)
                    .onAppear {
                        // Diese Funktion initialisiert den Player, setzt Mute und startet Autoplay.
                        setupPlayer(url: url)
                    }
                    // onDisappear wird jetzt vom .onDisappear des VStack gehandhabt
            } else {
                Text("Video URL ungültig").foregroundColor(.red)
            }
        } else {
            // AsyncImage für Bilder (unverändert)
            AsyncImage(url: item.imageUrl) { phase in
                switch phase {
                case .success(let image):
                    image.resizable().scaledToFit()
                case .failure:
                    Text("Bild konnte nicht geladen werden").foregroundColor(.red)
                default:
                    ProgressView()
                }
            }
            // WICHTIG: Stelle sicher, dass auch der Bild-Zweig den Player und Observer bereinigt,
            // falls der Benutzer schnell zwischen Bild- und Videoposts wechselt.
            .onAppear {
                 // Wenn wir zu einem Bild wechseln, soll ein eventuell laufender
                 // Player vom vorherigen Video gestoppt und der Observer entfernt werden.
                 cleanupPlayerAndObserver()
            }
        }
    }

    // Funktion zum Initialisieren und Konfigurieren des AVPlayers
    private func setupPlayer(url: URL) {
        // Nur neu erstellen, wenn nötig
        if player == nil || player?.currentItem?.asset != AVURLAsset(url: url) {
            print("Setting up new player for URL: \(url)")
            // Vorherigen Observer sicher entfernen, falls vorhanden
            self.muteObserver?.invalidate()
            self.muteObserver = nil

            player = AVPlayer(url: url)

            // 1. Stummschaltung basierend auf gespeicherter Einstellung anwenden
            player?.isMuted = settings.isVideoMuted
            print("Player initial mute state set to: \(settings.isVideoMuted)")

            // 2. Beobachter (KVO) für die 'isMuted'-Eigenschaft des Players hinzufügen
            // Wir wollen wissen, wann der *Benutzer* den Mute-Button im Player drückt.
            self.muteObserver = player?.observe(\.isMuted, options: [.new]) { observedPlayer, change in
                 guard let newMutedState = change.newValue else { return }

                 // Aktualisiere die globale Einstellung, wenn sie sich vom Player-Status unterscheidet.
                 // Dies passiert, wenn der Benutzer den Button drückt.
                 if settings.isVideoMuted != newMutedState {
                     print("User changed mute via player controls. New state: \(newMutedState)")
                     settings.isVideoMuted = newMutedState
                 }
            }

        } else {
             // Player existiert bereits für diese URL, setze Mute-Status erneut
             // (für den Fall, dass die Einstellung global geändert wurde, während dieser Player pausiert war)
             print("Reusing existing player. Setting mute state to: \(settings.isVideoMuted)")
             player?.isMuted = settings.isVideoMuted
        }

        // 3. Autoplay starten
        player?.play()
        print("Player started (Autoplay)")
    }

    // Funktion zum Aufräumen (Player stoppen, Observer entfernen)
    private func cleanupPlayerAndObserver() {
        print("Cleaning up player and observer.")
        player?.pause() // Video anhalten
        muteObserver?.invalidate() // KVO-Beobachtung beenden
        muteObserver = nil
        // Optional: Player auf nil setzen, um Ressourcen freizugeben, wenn gewünscht
        // player = nil
    }


    // Hilfsfunktion für das Seitenverhältnis (unverändert)
    private func guessAspectRatio() -> CGFloat? {
        if item.width > 0 && item.height > 0 {
            return CGFloat(item.width) / CGFloat(item.height)
        }
        return 16.0 / 9.0 // Fallback
    }
}

// MARK: - Preview

#Preview {
     let sampleVideoItem = Item(id: 2, image: "test.mp4", thumb: "tv.jpg", width: 1920, height: 1080, up: 20, down: 2)
     let sampleImageItem = Item(id: 1, image: "test.jpg", thumb: "t.jpg", width: 800, height: 1200, up: 10, down: 1)

    return NavigationStack { // Für eine realistischere Vorschauumgebung
        DetailViewContent(item: sampleVideoItem)
             // WICHTIG FÜR PREVIEW: Füge hier ein EnvironmentObject hinzu!
            .environmentObject(AppSettings()) // Erstellt eine temporäre Instanz für die Vorschau
    }
}
