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
        NavigationStack { // NavigationStack wird beibehalten für die Toolbar
            ZoomableScrollView(item: item, isLoading: $isLoading, errorMessage: $errorMessage)
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .background(Color.black) // Hintergrund füllt jetzt den gesamten Screen
                .overlay(loadingOrErrorOverlay) // Show loading/error indicators
                .toolbar {
                    ToolbarItem(placement: .navigationBarTrailing) {
                        Button {
                            dismiss()
                        } label: {
                            Image(systemName: "xmark")
                                .font(.headline.weight(.medium)) // KLEINERES ICON, z.B. .headline
                                .foregroundColor(.white)
                                .padding(8)
                                .background(.black.opacity(0.35))
                                .clipShape(Circle())
                        }
                        .accessibilityLabel("Schließen")
                    }
                }
                .toolbarBackground(.hidden, for: .navigationBar)
        }
        .ignoresSafeArea()
        .preferredColorScheme(.dark)
    }

    /// Overlay to display loading indicator or error message.
    @ViewBuilder
    private var loadingOrErrorOverlay: some View {
        if isLoading {
            ProgressView()
                .scaleEffect(1.5)
                .progressViewStyle(CircularProgressViewStyle(tint: .white))
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .background(Color.black.opacity(0.4))
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
            .background(Material.ultraThinMaterial)
            .cornerRadius(15)
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .background(Color.black.opacity(0.4))
        }
    }
}

// MARK: - Preview

#Preview {
    let sampleImageItem = Item(
        id: 1, promoted: 1001, userId: 1, down: 15, up: 150,
        created: Int(Date().timeIntervalSince1970) - 200,
        image: "efefd31e9c1f6518ca494ff8f569728b.jpg", thumb: "t1.jpg",
        fullsize: "efefd31e9c1f6518ca494ff8f569728b.jpg", preview: nil,
        width: 800, height: 600, audio: false, source: "http://example.com",
        flags: 1, user: "UserA", mark: 1, repost: nil,
        variants: nil,
        subtitles: nil,
        favorited: false
    )

    return FullscreenImageView(item: sampleImageItem)
}
// --- END OF COMPLETE FILE ---
