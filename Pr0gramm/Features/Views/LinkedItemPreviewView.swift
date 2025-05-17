// Pr0gramm/Pr0gramm/Features/Views/LinkedItemPreviewView.swift
// --- START OF COMPLETE FILE ---

import SwiftUI
import os

/// A view designed to be presented in a sheet, responsible for fetching
/// and displaying a single item referenced by its ID (typically from a link in a comment).
struct LinkedItemPreviewView: View {
    let itemID: Int // The ID of the item to fetch and display
    // --- MODIFIED: targetCommentID hinzugefügt ---
    let targetCommentID: Int? // Optional: Die ID des Kommentars, zu dem gescrollt werden soll
    // --- END MODIFICATION ---

    // MARK: - Environment & State
    @EnvironmentObject var settings: AppSettings
    @EnvironmentObject var authService: AuthService
    @Environment(\.dismiss) var dismiss // To close the sheet

    @State private var fetchedItem: Item? = nil // Holds the fetched item data
    @State private var isLoading = false
    @State private var errorMessage: String? = nil

    // ADD PlayerManager StateObject for the preview
    @StateObject private var playerManager = VideoPlayerManager()

    private let apiService = APIService()
    private static let logger = Logger(subsystem: Bundle.main.bundleIdentifier!, category: "LinkedItemPreviewView")
    
    // --- MODIFIED: Initializer aktualisiert ---
    init(itemID: Int, targetCommentID: Int? = nil) {
        self.itemID = itemID
        self.targetCommentID = targetCommentID
        LinkedItemPreviewView.logger.info("LinkedItemPreviewView init with itemID: \(itemID), targetCommentID: \(targetCommentID ?? -1)")
    }
    // --- END MODIFICATION ---

    // MARK: - Body
    var body: some View {
        Group {
            if isLoading {
                ProgressView("Lade Vorschau für \(itemID)...")
                    .frame(maxWidth: .infinity, maxHeight: .infinity) // Center the progress view
            } else if let error = errorMessage {
                // Display error state with retry option
                VStack {
                    Image(systemName: "exclamationmark.triangle.fill")
                        .font(.largeTitle)
                        .foregroundColor(.orange)
                        .padding(.bottom)
                    Text("Fehler beim Laden")
                        .font(UIConstants.headlineFont)
                    Text(error)
                        .font(.subheadline)
                        .foregroundColor(.secondary)
                        .multilineTextAlignment(.center)
                        .padding()
                    Button("Erneut versuchen") {
                        Task { await loadItem() } // Retry loading on button tap
                    }
                    .buttonStyle(.bordered)
                    .padding(.top)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity) // Center the error view
            } else if let item = fetchedItem {
                // --- MODIFIED: targetCommentID an PagedDetailViewWrapperForItem übergeben ---
                PagedDetailViewWrapperForItem(
                    item: item,
                    playerManager: playerManager,
                    targetCommentID: self.targetCommentID // Hier wird es übergeben
                )
                // --- END MODIFICATION ---
                // Environment objects (settings, authService) are passed down automatically
            } else {
                // Fallback if not loading, no error, but no item (initial state or unexpected issue)
                 Text("Vorschau wird vorbereitet...")
                     .foregroundColor(.secondary)
                     .frame(maxWidth: .infinity, maxHeight: .infinity)
            }
        }
        .task { // Use .task for automatic loading AND manager configuration
             // Configure the local player manager when the task starts
             playerManager.configure(settings: settings)
             // Load the item data
             await loadItem()
         }
    }

    // MARK: - Data Loading
    /// Fetches the item data from the API using the provided `itemID`.
    private func loadItem() async {
        if fetchedItem != nil || isLoading {
            LinkedItemPreviewView.logger.trace("loadItem skipped: Already loaded (\(fetchedItem != nil)) or already loading (\(isLoading)).")
             return
        }

        await MainActor.run {
            isLoading = true
            errorMessage = nil
        }
        LinkedItemPreviewView.logger.info("Fetching preview item with ID: \(itemID)")

        do {
            // --- MODIFIED: Flags für Detailansicht (z.B. alle) ---
            // Normalerweise möchte man hier alle Flags (31) verwenden, um sicherzustellen, dass das Item geladen wird,
            // unabhängig von den globalen Filtern des Nutzers, da es direkt verlinkt wurde.
            let flagsToFetchWith = 31 // SFW, NSFW, NSFL, NSFP, POL
            // --- END MODIFICATION ---
            let item = try await apiService.fetchItem(id: itemID, flags: flagsToFetchWith)

            await MainActor.run {
                if let fetched = item {
                    self.fetchedItem = fetched
                    LinkedItemPreviewView.logger.info("Successfully fetched preview item \(itemID)")
                } else {
                    // --- MODIFIED: Fehlerbehandlung, wenn Item nicht gefunden/Filter nicht passen ---
                    // Selbst mit allen Flags könnte ein Item nicht existieren (gelöscht etc.)
                    self.errorMessage = "Post konnte nicht gefunden werden."
                    LinkedItemPreviewView.logger.warning("Could not fetch preview item \(itemID). API returned nil even with all flags.")
                    // --- END MODIFICATION ---
                }
                isLoading = false
            }
        } catch let error as URLError where error.code == .userAuthenticationRequired {
             LinkedItemPreviewView.logger.error("Failed to fetch preview item \(itemID): Authentication required.")
             await MainActor.run {
                 self.errorMessage = "Sitzung abgelaufen. Bitte erneut anmelden."
                 isLoading = false
             }
        } catch {
            LinkedItemPreviewView.logger.error("Failed to fetch preview item \(itemID): \(error.localizedDescription)")
            await MainActor.run {
                self.errorMessage = "Netzwerkfehler: \(error.localizedDescription)"
                 isLoading = false
            }
        }
    }
}


// MARK: - Previews

#Preview("Loading") {
    // Directly instantiate LinkedItemPreviewView and provide environment objects
    LinkedItemPreviewView(itemID: 12345, targetCommentID: 67890) // Mit targetCommentID für Test
        .environmentObject(AppSettings())
        .environmentObject(AuthService(appSettings: AppSettings()))
}

#Preview("Error") {
    let settings = AppSettings()
    let auth = AuthService(appSettings: settings)
    LinkedItemPreviewView(itemID: 999)
        .environmentObject(settings)
        .environmentObject(auth)
}
// --- END OF COMPLETE FILE ---
