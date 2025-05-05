// Pr0gramm/Pr0gramm/Features/Views/FullscreenImageView.swift
// --- START OF COMPLETE FILE ---

import SwiftUI
import UIKit
import Kingfisher // Import Kingfisher
import os // Import os for logging

/// A view designed to be presented modally (e.g., in a sheet) to display
/// an image full-screen with zoom and pan capabilities.
struct FullscreenImageView: View {
    let item: Item // The item whose image to display
    @Environment(\.dismiss) var dismiss // Action to close the view

    @State private var isLoading = true // Track loading state for the zoomable view
    @State private var errorMessage: String? = nil // Track errors from the zoomable view

    var body: some View {
        NavigationStack {
            ZoomableScrollView(item: item, isLoading: $isLoading, errorMessage: $errorMessage)
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .background(Color.black) // Set background to black for fullscreen feel
                .ignoresSafeArea() // Extend to screen edges
                .overlay(loadingOrErrorOverlay) // Show loading/error indicators
                .toolbar {
                    ToolbarItem(placement: .navigationBarLeading) { // Changed placement
                        Button("Fertig") { dismiss() }
                            .font(UIConstants.bodyFont) // Use adaptive font
                            .foregroundColor(.white) // Ensure visibility on black background
                            .padding(EdgeInsets(top: 5, leading: 0, bottom: 5, trailing: 10)) // Add padding
                            .background(.black.opacity(0.3)) // Semi-transparent background
                            .clipShape(Capsule())
                    }
                }
                // Hide the default navigation bar background for a cleaner look
                .toolbarBackground(.hidden, for: .navigationBar)
        }
    }

    /// Overlay to display loading indicator or error message.
    @ViewBuilder
    private var loadingOrErrorOverlay: some View {
        if isLoading {
            ProgressView()
                .scaleEffect(1.5) // Make indicator slightly larger
                .progressViewStyle(CircularProgressViewStyle(tint: .white))
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .background(Color.black.opacity(0.4)) // Dim background slightly
        } else if let error = errorMessage {
            VStack {
                Image(systemName: "exclamationmark.triangle.fill")
                    .font(.largeTitle)
                    .foregroundColor(.orange)
                Text("Fehler")
                    .font(.headline).foregroundColor(.white)
                Text(error)
                    .font(.footnote).foregroundColor(.gray)
                    .multilineTextAlignment(.center)
                    .padding(.horizontal)
            }
            .padding()
            .background(Material.ultraThinMaterial) // Use a blurred background
            .cornerRadius(15)
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .background(Color.black.opacity(0.4)) // Dim background slightly
        }
    }
}

// MARK: - Preview

#Preview {
    // Sample item for preview
    let sampleImageItem = Item(
        id: 1, promoted: 1001, userId: 1, down: 15, up: 150,
        created: Int(Date().timeIntervalSince1970) - 200,
        image: "efefd31e9c1f6518ca494ff8f569728b.jpg", thumb: "t1.jpg",
        fullsize: "efefd31e9c1f6518ca494ff8f569728b.jpg", preview: nil,
        width: 800, height: 600, audio: false, source: "http://example.com",
        flags: 1, user: "UserA", mark: 1, repost: nil,
        variants: nil,
        subtitles: nil, // Add missing argument
        favorited: false
    )

    // --- FIX: Remove explicit return ---
    FullscreenImageView(item: sampleImageItem)
    // --- END FIX ---
}
// --- END OF COMPLETE FILE ---
