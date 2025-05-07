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
    @State private var isLoading = false
    @State private var errorMessage: String? = nil

    // ADD PlayerManager StateObject for the preview
    @StateObject private var playerManager = VideoPlayerManager()

    private let apiService = APIService()
    private static let logger = Logger(subsystem: Bundle.main.bundleIdentifier!, category: "LinkedItemPreviewView")

    // MARK: - Body
    var body: some View {
        // --- MODIFIED: Wrap content in NavigationStack for Toolbar ---
        NavigationStack {
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
                    // Use the *SHARED* wrapper view
                    PagedDetailViewWrapperForItem(
                        item: item,
                        playerManager: playerManager
                    )
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
            // --- Add Toolbar inside NavigationStack ---
             .navigationTitle("Vorschau")
             #if os(iOS)
             .navigationBarTitleDisplayMode(.inline)
             #endif
             .toolbar {
                 ToolbarItem(placement: .confirmationAction) { // Or .navigationBarLeading if preferred
                     Button("Fertig") { dismiss() }
                 }
             }
        } // --- End NavigationStack ---
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
            let currentFlags = settings.apiFlags
            let item = try await apiService.fetchItem(id: itemID, flags: currentFlags)

            await MainActor.run {
                if let fetched = item {
                    self.fetchedItem = fetched
                    LinkedItemPreviewView.logger.info("Successfully fetched preview item \(itemID)")
                } else {
                    self.errorMessage = "Post konnte nicht gefunden werden oder entspricht nicht deinen Filtern."
                    LinkedItemPreviewView.logger.warning("Could not fetch preview item \(itemID). API returned nil or filter mismatch.")
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

    // Wrapper definition PagedDetailViewWrapperForItem is now in Shared folder
}


// MARK: - Previews

#Preview("Loading") {
    // Directly instantiate LinkedItemPreviewView and provide environment objects
    LinkedItemPreviewView(itemID: 12345)
        .environmentObject(AppSettings())
        .environmentObject(AuthService(appSettings: AppSettings()))
}

#Preview("Error") {
    let settings = AppSettings()
    let auth = AuthService(appSettings: settings)
    // Simulate an error state by setting errorMessage after initial load in a real scenario,
    // or just show it directly for preview simplicity if the load logic isn't run in preview.
    // This preview will likely start in the initial "Vorschau wird vorbereitet..." state,
    // as loadItem isn't called automatically in previews unless inside a .task.
    // To preview the error *state*, you might need a more complex preview setup
    // that injects a specific state. For now, this shows the initial state.
    LinkedItemPreviewView(itemID: 999)
        .environmentObject(settings)
        .environmentObject(auth)
}

// --- REMOVED Preview Wrapper Struct ---
// The @MainActor struct LinkedItemPreviewWrapperView definition
// that was here previously has been removed to fix the redeclaration error.
// --- END REMOVED ---

// --- END OF COMPLETE FILE ---
