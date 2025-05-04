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
                // --- MODIFIED: Use the wrapper view ---
                // Display the fetched item using the wrapper that manages the binding
                PagedDetailViewWrapper(
                    fetchedItem: item,
                    playerManager: playerManager
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

    // --- NEW WRAPPER VIEW ---
    /// Helper wrapper view to manage the @State array needed for the PagedDetailView binding.
    private struct PagedDetailViewWrapper: View {
        /// State variable holding the array containing the single fetched item.
        @State var items: [Item]
        /// The player manager instance passed down.
        let playerManager: VideoPlayerManager

        /// Initializes the wrapper, creating the state array from the single item.
        init(fetchedItem: Item, playerManager: VideoPlayerManager) {
            // Initialize the @State variable with an array containing only the fetched item.
            self._items = State(initialValue: [fetchedItem])
            self.playerManager = playerManager
        }

        /// Dummy load more action, as it's not needed for a single item preview.
        func dummyLoadMore() async {
             // This function does nothing in the preview context.
             LinkedItemPreviewView.logger.trace("PagedDetailViewWrapper: dummyLoadMore called (no-op)")
        }

        var body: some View {
            // Instantiate PagedDetailView, passing the binding to the state array.
            PagedDetailView(
                items: $items, // Pass the binding to the wrapper's @State array
                selectedIndex: 0, // Always index 0 for the single item
                playerManager: playerManager,
                loadMoreAction: dummyLoadMore // Pass the dummy action
            )
        }
    }
    // --- END NEW WRAPPER VIEW ---
}


// MARK: - Previews

#Preview("Loading") {
    LinkedItemPreviewWrapperView(itemID: 12345)
        .environmentObject(AppSettings())
        .environmentObject(AuthService(appSettings: AppSettings()))
}

#Preview("Error") {
    let settings = AppSettings()
    let auth = AuthService(appSettings: settings)
    return LinkedItemPreviewWrapperView(itemID: 999)
        .environmentObject(settings)
        .environmentObject(auth)
}
// --- END OF COMPLETE FILE ---
