import Foundation
import SwiftData
import PencilKit

/// Persistent model representing a single sketch drawing.
/// Each document stores its PencilKit data locally and tracks
/// its corresponding Notion page ID for syncing.
@Model
final class SketchDocument {

    var id: UUID
    var title: String
    var drawingData: Data
    var notionPageID: String?
    var createdAt: Date
    var lastSyncedAt: Date?
    var thumbnailData: Data?
    var connectedPageIDs: [String] = []
    var connectedPageCache: [String: ConnectedPageInfo] = [:]

    init(
        title: String = "Untitled Sketch",
        drawingData: Data = Data(),
        notionPageID: String? = nil
    ) {
        self.id = UUID()
        self.title = title
        self.drawingData = drawingData
        self.notionPageID = notionPageID
        self.createdAt = Date()
        self.lastSyncedAt = nil
        self.thumbnailData = nil
        self.connectedPageIDs = []
        self.connectedPageCache = [:]
    }

    // MARK: - Drawing Convenience

    /// Deserializes the stored data into a `PKDrawing`.
    var drawing: PKDrawing {
        get {
            guard !drawingData.isEmpty else { return PKDrawing() }
            return (try? PKDrawing(data: drawingData)) ?? PKDrawing()
        }
        set {
            drawingData = (try? newValue.dataRepresentation()) ?? Data()
        }
    }
}

/// Helper struct for caching connected page details.
struct ConnectedPageInfo: Codable {
    let title: String
    let icon: String?
}
