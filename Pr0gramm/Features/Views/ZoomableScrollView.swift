// Pr0gramm/Pr0gramm/Features/MediaManagement/ZoomableScrollView.swift
// --- START OF COMPLETE FILE ---

import SwiftUI
import UIKit
import Kingfisher // Import Kingfisher

/// A UIViewRepresentable that wraps a UIScrollView to enable zooming and panning of an image.
struct ZoomableScrollView: UIViewRepresentable {
    let item: Item // Pass the item to get the image URL
    @Binding var isLoading: Bool // Indicate loading state
    @Binding var errorMessage: String? // Report errors

    func makeUIView(context: Context) -> UIScrollView {
        // Configure the UIScrollView
        let scrollView = UIScrollView()
        scrollView.delegate = context.coordinator // Set the coordinator as the delegate
        scrollView.maximumZoomScale = 4.0 // Allow zooming up to 4x
        scrollView.minimumZoomScale = 1.0
        scrollView.bouncesZoom = true
        scrollView.showsHorizontalScrollIndicator = false
        scrollView.showsVerticalScrollIndicator = false
        scrollView.clipsToBounds = true // Prevent content from drawing outside bounds

        // Configure the UIImageView inside the ScrollView
        let imageView = UIImageView()
        imageView.contentMode = .scaleAspectFit
        imageView.clipsToBounds = true
        imageView.isUserInteractionEnabled = true // Necessary for gestures like double-tap
        scrollView.addSubview(imageView)
        context.coordinator.imageView = imageView // Store image view in coordinator

        // --- Add Double Tap Gesture Recognizer ---
        let doubleTapRecognizer = UITapGestureRecognizer(target: context.coordinator, action: #selector(Coordinator.handleDoubleTap(_:)))
        doubleTapRecognizer.numberOfTapsRequired = 2
        imageView.addGestureRecognizer(doubleTapRecognizer)
        // -----------------------------------------

        context.coordinator.scrollView = scrollView // Store scroll view

        // Start loading the image
        context.coordinator.loadImage(item: item)

        return scrollView
    }

    func updateUIView(_ uiView: UIScrollView, context: Context) {
        // Optional: If the item could change while the view is visible,
        // reload the image here. For a modal sheet, this is less likely.
        // context.coordinator.loadImage(item: item)
    }

    func makeCoordinator() -> Coordinator {
        Coordinator(self, isLoading: $isLoading, errorMessage: $errorMessage)
    }

    // MARK: - Coordinator
    class Coordinator: NSObject, UIScrollViewDelegate {
        var parent: ZoomableScrollView
        weak var imageView: UIImageView?
        weak var scrollView: UIScrollView?
        @Binding var isLoading: Bool
        @Binding var errorMessage: String?

        init(_ parent: ZoomableScrollView, isLoading: Binding<Bool>, errorMessage: Binding<String?>) {
            self.parent = parent
            self._isLoading = isLoading
            self._errorMessage = errorMessage
        }

        /// Tells the delegate which view to zoom in or out.
        func viewForZooming(in scrollView: UIScrollView) -> UIView? {
            return imageView
        }

        /// Called when the zoom level changes. Can be used to center the image.
        func scrollViewDidZoom(_ scrollView: UIScrollView) {
            centerImage()
        }

        /// Called after the image finishes loading. Configures zoom scale and centers.
        func imageDidLoad(_ image: UIImage) {
            guard let imageView = imageView, let scrollView = scrollView else { return }

            // Update state on main thread
            DispatchQueue.main.async {
                self.isLoading = false
                self.errorMessage = nil
                imageView.image = image
                imageView.sizeToFit() // Adjust image view size to the loaded image

                // Set scroll view content size
                scrollView.contentSize = imageView.frame.size

                // Calculate initial zoom scale to fit the image
                self.updateMinZoomScaleForSize(scrollView.bounds.size)
                scrollView.zoomScale = scrollView.minimumZoomScale // Start zoomed out fully

                // Center the image initially
                self.centerImage()
                print("ZoomableScrollView: Image loaded and initial zoom/centering set.")
            }
        }

        /// Called if image loading fails.
        func imageLoadFailed(_ error: Error) {
             DispatchQueue.main.async {
                self.isLoading = false
                self.errorMessage = "Bild konnte nicht geladen werden: \(error.localizedDescription)"
                print("ZoomableScrollView: Image load failed - \(error.localizedDescription)")
            }
        }

        /// Calculates and updates the minimum zoom scale to fit the image within the given size.
        func updateMinZoomScaleForSize(_ size: CGSize) {
            guard let imageView = imageView, let image = imageView.image, let scrollView = scrollView else { return }

            let widthScale = size.width / image.size.width
            let heightScale = size.height / image.size.height
            let minScale = min(widthScale, heightScale)

            scrollView.minimumZoomScale = minScale
            // Ensure current zoom isn't less than the new minimum
            scrollView.zoomScale = max(scrollView.zoomScale, minScale)
        }

        /// Centers the image view within the scroll view's bounds.
        func centerImage() {
            guard let imageView = imageView, let scrollView = scrollView else { return }

            let scrollViewSize = scrollView.bounds.size
            let imageViewSize = imageView.frame.size

            let horizontalSpace = imageViewSize.width < scrollViewSize.width ? (scrollViewSize.width - imageViewSize.width) / 2 : 0
            let verticalSpace = imageViewSize.height < scrollViewSize.height ? (scrollViewSize.height - imageViewSize.height) / 2 : 0

            scrollView.contentInset = UIEdgeInsets(top: verticalSpace, left: horizontalSpace, bottom: verticalSpace, right: horizontalSpace)
        }

        /// Loads the image using Kingfisher. Prefers fullsize, falls back to image.
        func loadImage(item: Item) {
            guard let imageView = imageView else { return }

            // Determine the best URL
            var targetUrl: URL?
            if let fullsizeFilename = item.fullsize, !fullsizeFilename.isEmpty {
                // Assume fullsize images are on the main image domain
                targetUrl = URL(string: "https://img.pr0gramm.com/")?.appendingPathComponent(fullsizeFilename)
                print("ZoomableScrollView: Attempting to load fullsize image: \(targetUrl?.absoluteString ?? "nil")")
            } else {
                targetUrl = item.imageUrl // Fallback to regular image URL
                 print("ZoomableScrollView: Fullsize missing, attempting to load regular image: \(targetUrl?.absoluteString ?? "nil")")
            }

            guard let url = targetUrl else {
                imageLoadFailed(NSError(domain: "ZoomableScrollView", code: 0, userInfo: [NSLocalizedDescriptionKey: "Keine gültige Bild-URL gefunden."]))
                return
            }

             // Update state on main thread
            DispatchQueue.main.async {
                self.isLoading = true
                self.errorMessage = nil
            }

            // Use Kingfisher to download and set the image
            imageView.kf.indicatorType = .activity // Show loading indicator
            imageView.kf.setImage(with: url, options: [.transition(.fade(0.2))]) { [weak self] result in
                guard let self = self else { return }
                switch result {
                case .success(let value):
                    self.imageDidLoad(value.image)
                case .failure(let error):
                     // Don't report cancellation errors
                     if !error.isTaskCancelled && !error.isNotCurrentTask {
                        self.imageLoadFailed(error)
                     } else {
                          print("ZoomableScrollView: Image loading cancelled.")
                          // Reset loading state if cancelled
                           DispatchQueue.main.async { self.isLoading = false }
                     }
                }
            }
        }

        /// Handles double-tap gestures to zoom in or reset zoom.
        @objc func handleDoubleTap(_ recognizer: UITapGestureRecognizer) {
            guard let scrollView = scrollView else { return }
            if scrollView.zoomScale > scrollView.minimumZoomScale {
                // Zoom out
                scrollView.setZoomScale(scrollView.minimumZoomScale, animated: true)
            } else {
                // Zoom in to a specific point or a fixed scale (e.g., 2x)
                let zoomRect = zoomRectForScale(scale: scrollView.maximumZoomScale / 2, center: recognizer.location(in: recognizer.view))
                 scrollView.zoom(to: zoomRect, animated: true)
                // Alternative: Zoom to a fixed scale like 2x
                // scrollView.setZoomScale(2.0, animated: true)
            }
        }

        /// Calculates the rectangle to zoom into for a given scale and center point.
        private func zoomRectForScale(scale: CGFloat, center: CGPoint) -> CGRect {
            guard let imageView = imageView, let scrollView = scrollView else { return CGRect.zero }
            var zoomRect = CGRect.zero
            zoomRect.size.height = imageView.frame.size.height / scale
            zoomRect.size.width  = imageView.frame.size.width  / scale
            let newCenter = imageView.convert(center, from: scrollView)
            zoomRect.origin.x = newCenter.x - (zoomRect.size.width / 2.0)
            zoomRect.origin.y = newCenter.y - (zoomRect.size.height / 2.0)
            return zoomRect
        }
    }
}
// --- END OF COMPLETE FILE ---
