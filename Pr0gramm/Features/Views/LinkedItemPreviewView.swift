// Pr0gramm/Pr0gramm/Features/Views/LinkedItemPreviewView.swift
// --- START OF COMPLETE FILE ---

import SwiftUI
import os

/// A view designed to be presented in a sheet, fetching and displaying a single linked item.
struct LinkedItemPreviewView: View {
    let itemID: Int

    @EnvironmentObject var settings: AppSettings
    @EnvironmentObject var authService: AuthService
    @Environment(\.dismiss) var dismiss

    @State private var fetchedItem: Item? = nil
    @State private var isLoading = true
    @State private var errorMessage: String? = nil

    private let apiService = APIService()
    private static let logger = Logger(subsystem: Bundle.main.bundleIdentifier!, category: "LinkedItemPreviewView")

    var body: some View {
        Group {
            if isLoading {
                ProgressView("Lade Vorschau für \(itemID)...")
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else if let error = errorMessage {
                VStack {
                    Image(systemName: "exclamationmark.triangle.fill")
                        .font(.largeTitle)
                        .foregroundColor(.orange)
                        .padding(.bottom)
                    Text("Fehler beim Laden")
                        .font(.headline)
                    Text(error)
                        .font(.subheadline)
                        .foregroundColor(.secondary)
                        .multilineTextAlignment(.center)
                        .padding()
                    Button("Erneut versuchen") {
                        Task { await loadItem() }
                    }
                    .buttonStyle(.bordered)
                    .padding(.top)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else if let item = fetchedItem {
                // Zeige das Item in einer PagedDetailView (mit nur einem Element)
                // Wichtig: Eigene Instanz von PagedDetailView hier
                PagedDetailView(items: [item], selectedIndex: 0)
                    // Stelle sicher, dass diese Instanz auch die nötigen Objekte hat
                    // (Wird durch den Wrapper View sichergestellt)
            } else {
                // Sollte nicht passieren, wenn isLoading false und kein Fehler/Item da ist
                ContentUnavailableView("Inhalt nicht verfügbar", systemImage: "questionmark.diamond")
            }
        }
        .task { // .task wird automatisch bei Erscheinen ausgeführt
            await loadItem()
        }
    }

    private func loadItem() async {
        guard fetchedItem == nil else { return } // Nur laden, wenn noch nicht geladen

        await MainActor.run {
            isLoading = true
            errorMessage = nil
        }
        Self.logger.info("Fetching preview item with ID: \(itemID)")

        do {
            // Verwende die aktuellen Filter-Flags des Benutzers für den API-Aufruf
            let currentFlags = settings.apiFlags
            let item = try await apiService.fetchItem(id: itemID, flags: currentFlags)

            await MainActor.run {
                if let fetched = item {
                    self.fetchedItem = fetched
                    Self.logger.info("Successfully fetched preview item \(itemID)")
                } else {
                    // Item konnte nicht abgerufen werden (vielleicht wegen Filter oder gelöscht)
                    self.errorMessage = "Post konnte nicht gefunden werden oder entspricht nicht deinen Filtern."
                    Self.logger.warning("Could not fetch preview item \(itemID). API returned nil or filter mismatch.")
                }
                isLoading = false
            }
        } catch let error as URLError where error.code == .userAuthenticationRequired {
             Self.logger.error("Failed to fetch preview item \(itemID): Authentication required.")
             await MainActor.run {
                 self.errorMessage = "Sitzung abgelaufen. Bitte erneut anmelden."
                 isLoading = false
                 // Optional: Den Benutzer ausloggen, wenn die Session hier ungültig ist?
                 // Task { await authService.logout() }
             }
        } catch {
            Self.logger.error("Failed to fetch preview item \(itemID): \(error.localizedDescription)")
            await MainActor.run {
                self.errorMessage = "Netzwerkfehler: \(error.localizedDescription)"
                isLoading = false
            }
        }
    }
}

// Preview für LinkedItemPreviewView
#Preview("Loading") {
    // Preview benötigt Wrapper für Environment Objects
    LinkedItemPreviewWrapperView(itemID: 12345)
        .environmentObject(AppSettings())
        .environmentObject(AuthService(appSettings: AppSettings()))
}

#Preview("Error") {
    // Preview benötigt Wrapper für Environment Objects
     struct ErrorPreviewWrapper: View {
         @StateObject var settings = AppSettings()
         @StateObject var auth = AuthService(appSettings: AppSettings())

         var body: some View {
             // Modifiziere den Zustand, um einen Fehler zu simulieren
             // (Direkter State ist hier schwierig, daher nur Grundansicht)
             LinkedItemPreviewWrapperView(itemID: 999)
                 .environmentObject(settings)
                 .environmentObject(auth)
         }
     }
     return ErrorPreviewWrapper()
}
// --- END OF COMPLETE FILE ---
