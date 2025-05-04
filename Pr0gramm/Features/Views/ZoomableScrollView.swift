// Pr0gramm/Pr0gramm/Features/Views/ZoomableScrollView.swift
// --- START OF COMPLETE FILE ---

import SwiftUI
import UIKit
import Kingfisher // Import Kingfisher
import os // Import os for logging

/// A UIViewRepresentable that wraps a UIScrollView to enable zooming and panning of an image.
struct ZoomableScrollView: UIViewRepresentable {
    let item: Item // Pass the item to get the image URL
    @Binding var isLoading: Bool // Indicate loading state
    @Binding var errorMessage: String? // Report errors

    // --- Add Logger ---
    private static let logger = Logger(subsystem: Bundle.main.bundleIdentifier!, category: "ZoomableScrollView")
    // -----------------

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

        // Add Double Tap Gesture Recognizer
        let doubleTapRecognizer = UITapGestureRecognizer(target: context.coordinator, action: #selector(Coordinator.handleDoubleTap(_:)))
        doubleTapRecognizer.numberOfTapsRequired = 2
        imageView.addGestureRecognizer(doubleTapRecognizer)

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
        Coordinator(self, isLoading: $isLoading, errorMessage: $errorMessage, logger: Self.logger)
    }

    // MARK: - Coordinator
    class Coordinator: NSObject, UIScrollViewDelegate {
        var parent: ZoomableScrollView
        weak var imageView: UIImageView?
        weak var scrollView: UIScrollView?
        @Binding var isLoading: Bool
        @Binding var errorMessage: String?
        let logger: Logger // Add logger instance

        // --- Modified Init ---
        init(_ parent: ZoomableScrollView, isLoading: Binding<Bool>, errorMessage: Binding<String?>, logger: Logger) {
            self.parent = parent
            self._isLoading = isLoading
            self._errorMessage = errorMessage
            self.logger = logger // Store logger
        }
        // ---------------------

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
        func imageDidLoad() {
            guard let imageView = imageView, let scrollView = scrollView else { return }

            // Update state on main thread
            DispatchQueue.main.async {
                self.isLoading = false
                self.errorMessage = nil
                // imageView.image = image // Kingfisher sets this
                imageView.sizeToFit() // Adjust image view size based on the image set by Kingfisher

                // Set scroll view content size
                scrollView.contentSize = imageView.frame.size

                // Calculate initial zoom scale to fit the image
                self.updateMinZoomScaleForSize(scrollView.bounds.size)
                scrollView.zoomScale = scrollView.minimumZoomScale // Start zoomed out fully

                // Center the image initially
                self.centerImage()
                self.logger.info("Image loaded and initial zoom/centering set.")
            }
        }

        /// Called if image loading fails (after potential fallback).
        func finalImageLoadFailed(_ error: Error) {
             DispatchQueue.main.async {
                self.isLoading = false
                self.errorMessage = "Bild konnte nicht geladen werden: \(error.localizedDescription)"
                self.logger.error("Final image load failed: \(error.localizedDescription)")
            }
        }

        /// Calculates and updates the minimum zoom scale to fit the image within the given size.
        func updateMinZoomScaleForSize(_ size: CGSize) {
            guard let imageView = imageView, let image = imageView.image, image.size.width > 0, image.size.height > 0, let scrollView = scrollView else { return }

            let widthScale = size.width / image.size.width
            let heightScale = size.height / image.size.height
            let minScale = min(widthScale, heightScale)

             guard minScale.isFinite, minScale > 0 else {
                  logger.warning("Warning - Invalid minScale calculated (\(minScale)). Skipping zoom scale update.")
                  return
             }

            scrollView.minimumZoomScale = minScale
             if scrollView.zoomScale.isFinite, scrollView.zoomScale > 0 {
                 scrollView.zoomScale = max(scrollView.zoomScale, minScale)
             } else {
                 scrollView.zoomScale = minScale
             }
        }

        /// Centers the image view within the scroll view's bounds.
        func centerImage() {
            guard let imageView = imageView, let scrollView = scrollView else { return }

            let scrollViewSize = scrollView.bounds.size
            let imageViewSize = imageView.frame.size

             guard scrollViewSize.width > 0, scrollViewSize.height > 0 else { return }

            let horizontalSpace = imageViewSize.width < scrollViewSize.width ? (scrollViewSize.width - imageViewSize.width) / 2 : 0
            let verticalSpace = imageViewSize.height < scrollViewSize.height ? (scrollViewSize.height - imageViewSize.height) / 2 : 0

             let validHorizontalSpace = max(0, horizontalSpace.isFinite ? horizontalSpace : 0)
             let validVerticalSpace = max(0, verticalSpace.isFinite ? verticalSpace : 0)

            scrollView.contentInset = UIEdgeInsets(top: validVerticalSpace, left: validHorizontalSpace, bottom: validVerticalSpace, right: validHorizontalSpace)
        }

        // --- MODIFIED: loadImage function with Fallback Logic ---
        /// Loads the image using Kingfisher. Prefers fullsize, falls back to image on failure.
        func loadImage(item: Item) {
            guard let imageView = imageView else {
                 logger.error("loadImage called but imageView is nil.")
                 return
             }

            // 1. Determine URLs
            let fullsizeUrl: URL?
            if let fullsizeFilename = item.fullsize, !fullsizeFilename.isEmpty {
                fullsizeUrl = URL(string: "https://img.pr0gramm.com/")?.appendingPathComponent(fullsizeFilename)
            } else {
                fullsizeUrl = nil // Explicitly nil if not available
            }
            let regularImageUrl = item.imageUrl // Always have the regular URL as fallback

            // 2. Set initial loading state
            DispatchQueue.main.async {
                self.isLoading = true
                self.errorMessage = nil
                imageView.kf.indicatorType = .activity // Show loading indicator
            }

            // 3. Define the load function (to avoid repetition)
            func performLoad(url: URL?, isFallback: Bool) {
                guard let targetUrl = url else {
                    // If even the regular URL is nil, fail immediately
                    logger.error("Cannot load image for item \(item.id): Target URL is nil (isFallback: \(isFallback)).")
                    self.finalImageLoadFailed(NSError(domain: "ZoomableScrollView", code: 1, userInfo: [NSLocalizedDescriptionKey: "Bild-URL ungültig."]))
                    return
                }

                logger.info("Attempting to load image [isFallback=\(isFallback)] from: \(targetUrl.absoluteString)")

                imageView.kf.setImage(with: targetUrl, options: [.transition(.fade(0.2))]) { [weak self] result in
                    guard let self = self else { return }

                    switch result {
                    case .success:
                        self.logger.info("Successfully loaded image [isFallback=\(isFallback)].")
                        self.imageDidLoad() // Call common setup function

                    case .failure(let error):
                        // Ignore cancellation errors
                        if error.isTaskCancelled || error.isNotCurrentTask {
                            self.logger.info("Image loading cancelled [isFallback=\(isFallback)].")
                            // Optionally reset loading state if needed, depends on flow
                            // DispatchQueue.main.async { self.isLoading = false }
                            return
                        }

                        self.logger.warning("Failed to load image [isFallback=\(isFallback)] from \(targetUrl.absoluteString): \(error.localizedDescription)")

                        if !isFallback, let fallbackUrl = regularImageUrl {
                            // If the primary (fullsize) load failed, try the fallback (regular)
                            self.logger.info("Fullsize failed, attempting fallback to regular image.")
                            performLoad(url: fallbackUrl, isFallback: true)
                        } else {
                            // If this was already the fallback, or fallback URL is nil, then it's a final failure
                            self.finalImageLoadFailed(error)
                        }
                    }
                }
            }

            // 4. Start the loading process
            if let primaryUrl = fullsizeUrl {
                 // Try fullsize first
                 performLoad(url: primaryUrl, isFallback: false)
            } else {
                 // If no fullsize, go directly to regular image
                 logger.info("No fullsize URL available, loading regular image directly.")
                 performLoad(url: regularImageUrl, isFallback: true) // Treat as fallback for logic, though it's the primary attempt here
            }
        }
        // --- END MODIFIED loadImage ---


        /// Handles double-tap gestures to zoom in or reset zoom.
        @objc func handleDoubleTap(_ recognizer: UITapGestureRecognizer) {
            guard let scrollView = scrollView else { return }
            let tolerance: CGFloat = 0.001
            if scrollView.zoomScale > scrollView.minimumZoomScale + tolerance {
                scrollView.setZoomScale(scrollView.minimumZoomScale, animated: true)
            } else {
                let targetScale = max(scrollView.minimumZoomScale * 2.0, min(scrollView.maximumZoomScale, 2.0))
                let zoomRect = zoomRectForScale(scale: targetScale, center: recognizer.location(in: recognizer.view))
                if zoomRect != .zero {
                    scrollView.zoom(to: zoomRect, animated: true)
                }
            }
        }

        /// Calculates the rectangle to zoom into for a given scale and center point.
        private func zoomRectForScale(scale: CGFloat, center: CGPoint) -> CGRect {
            guard let imageView = imageView, let scrollView = scrollView, scale > 0 else { return CGRect.zero }
            var zoomRect = CGRect.zero
            guard imageView.frame.size.width > 0, imageView.frame.size.height > 0 else { return .zero }
            zoomRect.size.width = imageView.frame.size.width / scale
            zoomRect.size.height = imageView.frame.size.height / scale
             guard zoomRect.size.width.isFinite, zoomRect.size.width > 0,
                   zoomRect.size.height.isFinite, zoomRect.size.height > 0 else { return .zero }
            let centerInImageView = imageView.convert(center, from: scrollView)
            zoomRect.origin.x = centerInImageView.x - (zoomRect.size.width / 2.0)
            zoomRect.origin.y = centerInImageView.y - (zoomRect.size.height / 2.0)
             guard zoomRect.origin.x.isFinite, zoomRect.origin.y.isFinite else { return .zero }

             // Clamp the zoomRect to the bounds of the image
             let imageWidth = imageView.frame.width
             let imageHeight = imageView.frame.height
             if zoomRect.origin.x < 0 { zoomRect.origin.x = 0 }
             if zoomRect.origin.y < 0 { zoomRect.origin.y = 0 }
             if zoomRect.maxX > imageWidth { zoomRect.origin.x -= (zoomRect.maxX - imageWidth) }
             if zoomRect.maxY > imageHeight { zoomRect.origin.y -= (zoomRect.maxY - imageHeight) }

            return zoomRect
        }
    }
}
// --- END OF COMPLETE FILE ---
