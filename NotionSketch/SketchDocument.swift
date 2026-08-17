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

    // MARK: - Whiteboard Migration Properties
    // Additive stored properties for migration-safe SwiftData lightweight migration.
    // `contentVersion` gates old vs new storage: 0 = legacy PKDrawing-only, 1 = whiteboard JSON.
    // A layered whiteboard renderer will replace PKCanvasView in later tasks; until then,
    // PKCanvasView remains the "freehand layer" and renders whatever effectiveDrawingForLegacyCanvas returns.

    /// Serialized `WhiteboardDocument` JSON string. Nil for legacy documents.
    var whiteboardJSON: String? = nil

    /// Content format version: 0 = legacy PKDrawing-only, 1 = whiteboard JSON.
    var contentVersion: Int = 0

    /// When the sketch was last edited locally (drawing change or rename).
    /// Compared against the Notion page's last-edited time for last-write-wins pulls.
    /// Additive optional property — migration-safe like the whiteboard properties above.
    var lastEditedLocally: Date? = nil

    init(
        title: String = "Untitled Sketch",
        drawingData: Data = Data(),
        notionPageID: String? = nil,
        syncedBlockID: String? = nil
    ) {
        self.id = UUID()
        self.title = title
        self.drawingData = drawingData
        self.notionPageID = notionPageID
        self.syncedBlockID = syncedBlockID
        self.createdAt = Date()
        self.lastSyncedAt = nil
        self.thumbnailData = nil
    }

    // MARK: - Drawing Convenience

    /// Deserializes the stored data into a `PKDrawing`.
    var drawing: PKDrawing {
        get {
            guard !drawingData.isEmpty else { return PKDrawing() }
            return (try? PKDrawing(data: drawingData)) ?? PKDrawing()
        }
        set {
            drawingData = newValue.dataRepresentation()
        }
    }
    
    // MARK: - Whiteboard Computed Properties
    // These are computed (not persisted) — SwiftData ignores them, which is intended.

    /// Decodes `whiteboardJSON` into a `WhiteboardDocument`.
    /// Setting a non-nil document also bumps `contentVersion` to 1.
    var whiteboard: WhiteboardDocument? {
        get {
            guard let json = whiteboardJSON else { return nil }
            return WhiteboardDocument.fromJSONString(json)
        }
        set {
            if let doc = newValue {
                whiteboardJSON = doc.toJSONString()
                contentVersion = 1
            } else {
                whiteboardJSON = nil
            }
        }
    }

    /// Returns the drawing that should be shown on the legacy PKCanvasView.
    /// - If `contentVersion == 1` and there is at least one `.freehandPencilKit` object,
    ///   decodes the lowest-zIndex freehand object's Base64 `PKDrawing` and returns it.
    /// - Otherwise falls back to the legacy `drawing`.
    var effectiveDrawingForLegacyCanvas: PKDrawing {
        if contentVersion == 1, let wb = whiteboard {
            // Find the lowest-zIndex freehandPencilKit object for legacy canvas rendering.
            let freehandObjects = wb.objects
                .compactMap { obj -> (WhiteboardObject, String)? in
                    if case .freehandPencilKit(let base64) = obj.kind {
                        return (obj, base64)
                    }
                    return nil
                }
                .sorted { a, b in
                    if a.0.zIndex != b.0.zIndex { return a.0.zIndex < b.0.zIndex }
                    if a.0.createdAt != b.0.createdAt { return a.0.createdAt < b.0.createdAt }
                    return a.0.id.uuidString < b.0.id.uuidString
                }

            if let (_, base64) = freehandObjects.first,
               let data = Data(base64Encoded: base64),
               let drawing = try? PKDrawing(data: data) {
                return drawing
            }
        }

        return drawing
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
        let padding: CGFloat = 20
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
