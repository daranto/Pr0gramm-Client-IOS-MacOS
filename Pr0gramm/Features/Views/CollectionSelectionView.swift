// Pr0gramm/Pr0gramm/Features/Views/CollectionSelectionView.swift
// --- START OF COMPLETE FILE ---

import SwiftUI
import os

/// A view presented as a sheet to allow the user to select a collection
/// to which an item should be added.
struct CollectionSelectionView: View {
    let item: Item // The item to be added
    let onCollectionSelected: (ApiCollection) -> Void // Callback when a collection is chosen

    @EnvironmentObject var authService: AuthService
    @EnvironmentObject var settings: AppSettings // For API flags or other general settings if needed by API calls indirectly
    @Environment(\.dismiss) var dismiss

    private static let logger = Logger(subsystem: Bundle.main.bundleIdentifier!, category: "CollectionSelectionView")

    private var availableCollections: [ApiCollection] {
        // Filter out any collections that might not be suitable or sort them if needed
        // For now, just use all collections from AuthService
        return authService.userCollections.sorted { $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending }
    }

    var body: some View {
        NavigationStack {
            List {
                if availableCollections.isEmpty {
                    Text("Du hast noch keine Sammlungen erstellt.")
                        .foregroundColor(.secondary)
                        .padding()
                } else {
                    ForEach(availableCollections) { collection in
                        Button {
                            CollectionSelectionView.logger.info("User selected collection '\(collection.name)' (ID: \(collection.id)) for item \(item.id).")
                            onCollectionSelected(collection)
                            dismiss()
                        } label: {
                            HStack {
                                Text(collection.name)
                                    .font(UIConstants.bodyFont)
                                Spacer()
                                // Optionally show if item is already in this collection (more complex, needs more state)
                                // For now, just a simple list
                                if collection.id == settings.selectedCollectionIdForFavorites {
                                    Image(systemName: "star.fill")
                                        .foregroundColor(.yellow)
                                        .font(.caption)
                                        .accessibilityLabel("Standard Favoriten-Ordner")
                                }
                            }
                            .contentShape(Rectangle()) // Make the whole row tappable
                        }
                        .buttonStyle(.plain) // Use plain style to make it look like a list item
                    }
                }
            }
            .navigationTitle("Sammlung auswählen")
            #if os(iOS)
            .navigationBarTitleDisplayMode(.inline)
            #endif
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Abbrechen") {
                        dismiss()
                    }
                }
            }
            .onAppear {
                CollectionSelectionView.logger.debug("CollectionSelectionView appeared for item \(item.id). Available collections: \(availableCollections.count)")
            }
        }
    }
}

// MARK: - Preview
#Preview {
    // Preview requires a bit of setup for AuthService and an Item
    struct CollectionSelectionPreviewWrapper: View {
        @StateObject var authService: AuthService
        @StateObject var settings = AppSettings() // Add AppSettings for preview
        let sampleItem = Item(id: 123, promoted: nil, userId: 1, down: 0, up: 10, created: 0, image: "test.jpg", thumb: "test_thumb.jpg", fullsize: nil, preview: nil, width: 100, height: 100, audio: false, source: nil, flags: 1, user: "Test", mark: 1, repost: nil, variants: nil, subtitles: nil)

        init() {
            let tempSettings = AppSettings() // Create AppSettings instance
            let tempAuthService = AuthService(appSettings: tempSettings) // Pass it to AuthService
            tempAuthService.isLoggedIn = true
            tempAuthService.currentUser = UserInfo(id: 1, name: "PreviewUser", registered: 0, score: 0, mark: 1, badges: nil)
            tempAuthService.userNonce = "preview_nonce"
            
            // Populate userCollections for the preview
            let collections = [
                ApiCollection(id: 1, name: "Meine Standard Favoriten", keyword: "default", isPublic: 0, isDefault: 1, itemCount: 10),
                ApiCollection(id: 2, name: "Lustige Bilder", keyword: "funny", isPublic: 0, isDefault: 0, itemCount: 5),
                ApiCollection(id: 3, name: "Wallpapers", keyword: "wall", isPublic: 1, isDefault: 0, itemCount: 20)
            ]
            #if DEBUG
            tempAuthService.setUserCollectionsForPreview(collections)
            #endif
            
            // Set the default collection in AppSettings for the star icon
            tempSettings.selectedCollectionIdForFavorites = 1


            _authService = StateObject(wrappedValue: tempAuthService)
            _settings = StateObject(wrappedValue: tempSettings) // Store AppSettings
        }

        var body: some View {
            // Simulate presenting as a sheet
            VStack {
                Text("Parent View")
            }
            .sheet(isPresented: .constant(true)) {
                CollectionSelectionView(item: sampleItem) { selectedCollection in
                    print("Preview: Collection '\(selectedCollection.name)' selected for item \(sampleItem.id)")
                }
                .environmentObject(authService)
                .environmentObject(settings) // Provide AppSettings to the sheet environment
            }
        }
    }

    return CollectionSelectionPreviewWrapper()
}

// --- END OF COMPLETE FILE ---
