import Foundation
import CoreGraphics

/// Centralized constants for the NotionSketch application.
/// Organizes magic numbers and configuration values to improve maintainability.
enum AppConstants {

    enum Canvas {
        /// Drawable canvas size — large enough to feel infinite.
        static let size: CGFloat = 8000

        /// Spacing between dots in the background grid.
        static let dotSpacing: CGFloat = 40

        /// Radius of each dot in the background grid.
        static let dotRadius: CGFloat = 1.5

        /// Padding used when zooming to fit a drawing.
        static let fitPadding: CGFloat = 50

        /// Minimum allowed zoom scale for the canvas.
        static let minZoom: CGFloat = 0.2

        /// Maximum allowed zoom scale for the canvas.
        static let maxZoom: CGFloat = 3.0

        /// Default zoom level when centering the canvas.
        static let defaultZoom: CGFloat = 0.5

        /// Minimum movement threshold to trigger stabilization.
        static let stabilizationThreshold: CGFloat = 0.1

        /// Duration for canvas-related animations.
        static let animationDuration: Double = 0.3
    }

    enum Thumbnail {
        /// Padding around the drawing when generating a preview thumbnail.
        static let padding: CGFloat = 10

        /// Maximum dimension (width or height) for the generated thumbnail.
        static let maxDimension: CGFloat = 300

        /// Padding used for thumbnails stored in the document.
        static let documentPadding: CGFloat = 20
    }

    enum Sync {
        /// Delay before an automatic sync is triggered after a drawing change.
        static let debounceDelay: Duration = .seconds(10)

        /// Duration the success indicator remains visible after a successful sync.
        static let successDismissDelay: Duration = .seconds(4)

        /// Delay between processing individual pages during a library sync.
        static let librarySyncDelay: Duration = .milliseconds(100)

        /// Padding around the drawing when generating the full-resolution image for Notion.
        static let imagePadding: CGFloat = 20

        /// Scale factor for the full-resolution image exported to Notion.
        static let imageScale: CGFloat = 2.0
    }
}
