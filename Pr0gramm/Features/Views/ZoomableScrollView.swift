// Pr0gramm/Pr0gramm/Features/Views/ZoomableScrollView.swift
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

        // Ensure minimum zoom scale is updated if the view bounds change (e.g., rotation)
        context.coordinator.updateMinZoomScaleForSize(uiView.bounds.size)
        context.coordinator.centerImage() // Re-center after potential bounds change
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

        /// Called when the zoom level changes. Used to center the image during/after zoom.
        func scrollViewDidZoom(_ scrollView: UIScrollView) {
            centerImage()
        }

        /// Called *after* Kingfisher has successfully loaded and set the image on the `imageView`.
        /// Configures zoom scale and centers the image view.
        /// **REMOVED** the `image` parameter as Kingfisher handles setting the image directly.
        func imageDidLoad() {
            guard let imageView = imageView, let scrollView = scrollView else { return }

            // Update state on main thread
            DispatchQueue.main.async {
                self.isLoading = false
                self.errorMessage = nil
                // imageView.image = image // <-- REMOVED: Kingfisher sets this automatically (static or animated)
                imageView.sizeToFit() // Adjust image view size based on the image set by Kingfisher

                // Set scroll view content size
                scrollView.contentSize = imageView.frame.size

                // Calculate initial zoom scale to fit the image
                self.updateMinZoomScaleForSize(scrollView.bounds.size)
                scrollView.zoomScale = scrollView.minimumZoomScale // Start zoomed out fully

                // Center the image initially
                self.centerImage()
                print("ZoomableScrollView: Image loaded and initial zoom/centering set (via imageDidLoad).")
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
            guard let imageView = imageView, let image = imageView.image, image.size.width > 0, image.size.height > 0, let scrollView = scrollView else { return }

            let widthScale = size.width / image.size.width
            let heightScale = size.height / image.size.height
            let minScale = min(widthScale, heightScale)

            // Check if scales are valid before setting
             guard minScale.isFinite, minScale > 0 else {
                  print("ZoomableScrollView: Warning - Invalid minScale calculated (\(minScale)). Skipping zoom scale update.")
                  return
             }

            scrollView.minimumZoomScale = minScale
            // Ensure current zoom isn't less than the new minimum, only if current zoom is valid
             if scrollView.zoomScale.isFinite, scrollView.zoomScale > 0 {
                 scrollView.zoomScale = max(scrollView.zoomScale, minScale)
             } else {
                 // If current zoomScale is invalid (e.g., 0), set it to the new minimum
                 scrollView.zoomScale = minScale
             }
        }

        /// Centers the image view within the scroll view's bounds.
        func centerImage() {
            guard let imageView = imageView, let scrollView = scrollView else { return }

            let scrollViewSize = scrollView.bounds.size
            // Use imageView's frame size which reflects the zoom level
            let imageViewSize = imageView.frame.size

            // Ensure sizes are valid before calculation
             guard scrollViewSize.width > 0, scrollViewSize.height > 0 else { return }

            let horizontalSpace = imageViewSize.width < scrollViewSize.width ? (scrollViewSize.width - imageViewSize.width) / 2 : 0
            let verticalSpace = imageViewSize.height < scrollViewSize.height ? (scrollViewSize.height - imageViewSize.height) / 2 : 0

            // Ensure spaces are non-negative and finite
             let validHorizontalSpace = max(0, horizontalSpace.isFinite ? horizontalSpace : 0)
             let validVerticalSpace = max(0, verticalSpace.isFinite ? verticalSpace : 0)

            scrollView.contentInset = UIEdgeInsets(top: validVerticalSpace, left: validHorizontalSpace, bottom: validVerticalSpace, right: validHorizontalSpace)
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
                case .success:
                    // --- MODIFIED: Call imageDidLoad without passing the image ---
                    self.imageDidLoad()
                    // --- END MODIFICATION ---
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
             // Use a small tolerance to compare zoom scales to avoid floating point issues
            let tolerance: CGFloat = 0.001
            if scrollView.zoomScale > scrollView.minimumZoomScale + tolerance {
                // Zoom out
                scrollView.setZoomScale(scrollView.minimumZoomScale, animated: true)
            } else {
                // Zoom in to a specific point or a fixed scale (e.g., 2x)
                // Calculate a moderate zoom scale, e.g., half way to max zoom
                let targetScale = max(scrollView.minimumZoomScale * 2.0, min(scrollView.maximumZoomScale, 2.0)) // Zoom to 2x or max/2, whichever is appropriate
                let zoomRect = zoomRectForScale(scale: targetScale, center: recognizer.location(in: recognizer.view))
                if zoomRect != .zero { // Ensure zoomRect is valid
                    scrollView.zoom(to: zoomRect, animated: true)
                }
                // Alternative: Zoom to a fixed scale like 2x
                // scrollView.setZoomScale(2.0, animated: true)
            }
        }

        /// Calculates the rectangle to zoom into for a given scale and center point.
        private func zoomRectForScale(scale: CGFloat, center: CGPoint) -> CGRect {
            guard let imageView = imageView, let scrollView = scrollView, scale > 0 else { return CGRect.zero }

            var zoomRect = CGRect.zero

            // Ensure imageView has a valid frame size
            guard imageView.frame.size.width > 0, imageView.frame.size.height > 0 else { return .zero }

            // Calculate the size of the zoom rectangle in the coordinate system of the imageView
            zoomRect.size.width = imageView.frame.size.width / scale
            zoomRect.size.height = imageView.frame.size.height / scale

            // Ensure the calculated size is valid
             guard zoomRect.size.width.isFinite, zoomRect.size.width > 0,
                   zoomRect.size.height.isFinite, zoomRect.size.height > 0 else { return .zero }

            // Convert the tap location (center) from the scrollView's coordinate system
            // to the imageView's coordinate system.
            let centerInImageView = imageView.convert(center, from: scrollView)

            // Calculate the origin of the zoom rectangle
            zoomRect.origin.x = centerInImageView.x - (zoomRect.size.width / 2.0)
            zoomRect.origin.y = centerInImageView.y - (zoomRect.size.height / 2.0)

            // Ensure the origin is valid
             guard zoomRect.origin.x.isFinite, zoomRect.origin.y.isFinite else { return .zero }


            // --- Clamp the zoomRect to the bounds of the image ---
             let imageWidth = imageView.frame.width
             let imageHeight = imageView.frame.height

             if zoomRect.origin.x < 0 { zoomRect.origin.x = 0 }
             if zoomRect.origin.y < 0 { zoomRect.origin.y = 0 }

             if zoomRect.maxX > imageWidth { zoomRect.origin.x -= (zoomRect.maxX - imageWidth) }
             if zoomRect.maxY > imageHeight { zoomRect.origin.y -= (zoomRect.maxY - imageHeight) }
             // --- End Clamping ---


            return zoomRect
        }
    }
}
// --- END OF COMPLETE FILE ---
