// Pr0gramm/Pr0gramm/Features/Views/LinkedItemPreviewView.swift
// --- START OF COMPLETE FILE ---

import SwiftUI
import os

/// A view designed to be presented in a sheet, responsible for fetching
/// and displaying a single item referenced by its ID (typically from a link in a comment).
struct LinkedItemPreviewView: View {
    let itemID: Int // The ID of the item to fetch and display
    // --- NEW: Add targetCommentID ---
    let targetCommentID: Int? // Optional comment ID to scroll to
    // --- END NEW ---

    // MARK: - Environment & State
    @EnvironmentObject var settings: AppSettings
    @EnvironmentObject var authService: AuthService
    @Environment(\.dismiss) var dismiss // To close the sheet

    @State private var fetchedItem: Item? = nil // Holds the fetched item data
    @State private var isLoading = false
    @State private var errorMessage: String? = nil

    @StateObject private var playerManager = VideoPlayerManager()

    private let apiService = APIService()
    private static let logger = Logger(subsystem: Bundle.main.bundleIdentifier!, category: "LinkedItemPreviewView")

    // --- NEW: Initializer to accept targetCommentID ---
    init(itemID: Int, targetCommentID: Int? = nil) {
        self.itemID = itemID
        self.targetCommentID = targetCommentID
        LinkedItemPreviewView.logger.debug("LinkedItemPreviewView init. itemID: \(itemID), targetCommentID: \(targetCommentID ?? -1)")
    }
    // --- END NEW ---

    // MARK: - Body
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
                        .font(UIConstants.headlineFont)
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
                // --- MODIFIED: Pass targetCommentID to PagedDetailViewWrapperForItem ---
                PagedDetailViewWrapperForItem(
                    item: item,
                    playerManager: playerManager,
                    targetCommentID: self.targetCommentID // Pass it here
                )
                // --- END MODIFICATION ---
            } else {
                 Text("Vorschau wird vorbereitet...")
                     .foregroundColor(.secondary)
                     .frame(maxWidth: .infinity, maxHeight: .infinity)
            }
        }
        .task {
             playerManager.configure(settings: settings)
             await loadItem()
         }
    }

    // MARK: - Data Loading
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
}


// MARK: - Previews

#Preview("Loading") {
    // --- MODIFIED: Preview initialisiert mit targetCommentID ---
    LinkedItemPreviewView(itemID: 12345, targetCommentID: 67890) // Beispielhafte commentID
        .environmentObject(AppSettings())
        .environmentObject(AuthService(appSettings: AppSettings()))
    // --- END MODIFICATION ---
}

#Preview("Error") {
    let settings = AppSettings()
    let auth = AuthService(appSettings: settings)
    // --- MODIFIED: Preview initialisiert mit targetCommentID (auch wenn Fehler) ---
    LinkedItemPreviewView(itemID: 999, targetCommentID: nil)
    // --- END MODIFICATION ---
        .environmentObject(settings)
        .environmentObject(auth)
}
// --- END OF COMPLETE FILE ---
