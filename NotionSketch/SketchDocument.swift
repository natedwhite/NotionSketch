import Foundation
import SwiftData
import PencilKit
import UIKit

/// Persistent model representing a single sketch drawing.
/// Each document stores its PencilKit data locally and tracks
/// its corresponding Notion page ID for syncing.
@Model
final class SketchDocument {

    var id: UUID
    var title: String
    var drawingData: Data
    var notionPageID: String?
    var syncedBlockID: String?
    var createdAt: Date
    var lastSyncedAt: Date?
    var thumbnailData: Data?
    var connectedPageIDs: [String] = []
    var connectedPageCache: [String: ConnectedPageInfo] = [:]

    init(
        title: String = "Untitled Sketch",
        drawingData: Data = Data(),
        notionPageID: String? = nil,
        syncedBlockID: String? = nil,
        cachedDrawing: PKDrawing? = nil
    ) {
        self.id = UUID()
        self.title = title
        self.drawingData = drawingData
        self._cachedDrawing = cachedDrawing
        self.notionPageID = notionPageID
        self.syncedBlockID = syncedBlockID
        self.createdAt = Date()
        self.lastSyncedAt = nil
        self.thumbnailData = nil
        self.connectedPageIDs = []
        self.connectedPageCache = [:]
    }

    // MARK: - Drawing Convenience

    @Transient
    private var _cachedDrawing: PKDrawing?

    /// Deserializes the stored data into a `PKDrawing`.
    var drawing: PKDrawing {
        get {
            if let cached = _cachedDrawing {
                return cached
            }
            let newDrawing: PKDrawing
            if drawingData.isEmpty {
                newDrawing = PKDrawing()
            } else {
                newDrawing = (try? PKDrawing(data: drawingData)) ?? PKDrawing()
            }
            _cachedDrawing = newDrawing
            return newDrawing
        }
        set {
            _cachedDrawing = newValue
            drawingData = newValue.dataRepresentation()
        }
    }
    
    // MARK: - Thumbnail
    
    /// Re-generates the thumbnail data from the current drawing.
    /// This should be called on the Main Actor because PKDrawing image generation uses hidden UI logic.
    @MainActor
    func updateThumbnail() {
        let drawing = self.drawing
        let bounds = drawing.bounds
        
        // If empty, clear thumbnail
        if bounds.isEmpty || bounds.width < 1 || bounds.height < 1 {
            self.thumbnailData = nil
            return
        }
        
        // Add some padding
        let padding: CGFloat = AppConstants.Thumbnail.documentPadding
        let imageRect = CGRect(
            x: bounds.origin.x - padding,
            y: bounds.origin.y - padding,
            width: bounds.width + padding * 2,
            height: bounds.height + padding * 2
        )
        
        // Generate Image (Scale 1.0 for thumbnail is usually fine)
        let image = drawing.image(from: imageRect, scale: 1.0)
        
        // Convert to PNG data
        self.thumbnailData = image.pngData()
    }
}

/// Helper struct for caching connected page details.
struct ConnectedPageInfo: Codable {
    let title: String
    let icon: String?
}
