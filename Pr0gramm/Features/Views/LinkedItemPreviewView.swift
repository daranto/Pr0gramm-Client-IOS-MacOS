// Pr0gramm/Pr0gramm/Features/Views/LinkedItemPreviewView.swift
// --- START OF COMPLETE FILE ---

import SwiftUI
import os

/// A view designed to be presented in a sheet, responsible for fetching
/// and displaying a single item referenced by its ID (typically from a link in a comment).
struct LinkedItemPreviewView: View {
    let itemID: Int // The ID of the item to fetch and display

    // MARK: - Environment & State
    @EnvironmentObject var settings: AppSettings
    @EnvironmentObject var authService: AuthService
    @Environment(\.dismiss) var dismiss // To close the sheet

    @State private var fetchedItem: Item? = nil // Holds the fetched item data
    @State private var isLoading = true
    @State private var errorMessage: String? = nil

    // --- ADD PlayerManager StateObject for the preview ---
    @StateObject private var playerManager = VideoPlayerManager()
    // ------------------------------------------------------

    private let apiService = APIService()
    private static let logger = Logger(subsystem: Bundle.main.bundleIdentifier!, category: "LinkedItemPreviewView")

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
                // Display the fetched item using PagedDetailView
                // ** PASS the newly created playerManager to the PagedDetailView **
                PagedDetailView(
                    items: [item],
                    selectedIndex: 0,
                    playerManager: playerManager // <-- Pass the local manager instance
                )
                // Environment objects (settings, authService) are passed down automatically
            } else {
                // Fallback if not loading, no error, but no item (should ideally not happen)
                ContentUnavailableView("Inhalt nicht verfügbar", systemImage: "questionmark.diamond")
            }
        }
        .task { // Use .task for automatic loading AND manager configuration
             // Configure the local player manager when the task starts
             await playerManager.configure(settings: settings)
             // Load the item data
             await loadItem()
         }
        // Removed onAppear configuration, handled in .task now
    }

    // MARK: - Data Loading
    /// Fetches the item data from the API using the provided `itemID`.
    private func loadItem() async {
        // Avoid redundant fetches if already loaded or currently loading
        // Reset loading state only if not already loading
        if isLoading { return }
        if fetchedItem != nil {
            // If item is already fetched, ensure loading is false and return
            await MainActor.run { isLoading = false }
             return
        }

        // Reset state before loading
        await MainActor.run {
            isLoading = true
            errorMessage = nil
        }
        LinkedItemPreviewView.logger.info("Fetching preview item with ID: \(itemID)") // Use explicit type name

        do {
            // Use the user's current content filters for the API request
            let currentFlags = settings.apiFlags
            let item = try await apiService.fetchItem(id: itemID, flags: currentFlags)

            await MainActor.run {
                if let fetched = item {
                    self.fetchedItem = fetched
                    LinkedItemPreviewView.logger.info("Successfully fetched preview item \(itemID)") // Use explicit type name
                } else {
                    // API returned nil, likely due to filters or item deletion
                    self.errorMessage = "Post konnte nicht gefunden werden oder entspricht nicht deinen Filtern."
                    LinkedItemPreviewView.logger.warning("Could not fetch preview item \(itemID). API returned nil or filter mismatch.") // Use explicit type name
                }
                isLoading = false
            }
        } catch let error as URLError where error.code == .userAuthenticationRequired {
             // Handle expired session specifically
             LinkedItemPreviewView.logger.error("Failed to fetch preview item \(itemID): Authentication required.") // Use explicit type name
             await MainActor.run {
                 self.errorMessage = "Sitzung abgelaufen. Bitte erneut anmelden."
                 isLoading = false
             }
        } catch {
            // Handle generic network or decoding errors
            LinkedItemPreviewView.logger.error("Failed to fetch preview item \(itemID): \(error.localizedDescription)") // Use explicit type name
            await MainActor.run {
                self.errorMessage = "Netzwerkfehler: \(error.localizedDescription)"
                isLoading = false
            }
        }
    }
}

// MARK: - Previews

#Preview("Loading") {
    // Preview requires the wrapper to provide environment objects correctly
    LinkedItemPreviewWrapperView(itemID: 12345)
        .environmentObject(AppSettings())
        .environmentObject(AuthService(appSettings: AppSettings()))
}

#Preview("Error") {
    // Setup services directly within the preview provider
    let settings = AppSettings()
    let auth = AuthService(appSettings: settings)

    // Simulate an error state (if needed, though the view handles its own loading/errors)
    // Note: Direct state manipulation is hard here as the view loads internally.

    return LinkedItemPreviewWrapperView(itemID: 999) // Use a dummy ID for error preview
        .environmentObject(settings)
        .environmentObject(auth)
}
// --- END OF COMPLETE FILE ---
