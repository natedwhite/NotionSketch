import Foundation
import PencilKit
import Vision
import UIKit
import Observation

// MARK: - Sync State

/// Represents the current state of the sync engine.
enum SyncState: Equatable {
    case idle
    case syncing
    case success
    case error(String)

    var displayText: String {
        switch self {
        case .idle:
            return ""
        case .syncing:
            return "Syncing…"
        case .success:
            return "Synced ✓"
        case .error(let message):
            return "Error: \(message)"
        }
    }

    var iconName: String {
        switch self {
        case .idle:       return ""
        case .syncing:    return "arrow.triangle.2.circlepath"
        case .success:    return "checkmark.circle.fill"
        case .error:      return "exclamationmark.triangle.fill"
        }
    }
}

// MARK: - CanvasViewModel

/// Central logic layer managing PencilKit drawing state, debounced syncing,
/// on-device OCR via Vision, and Notion API orchestration.
///
/// Each instance is bound to a `SketchDocument` — it loads the saved drawing
/// on init and persists changes back to SwiftData.
@Observable
@MainActor
final class CanvasViewModel {

    // MARK: - Published State
    
    /// Current sync state — drives the UI status indicator.
    var syncState: SyncState {
        NotionSyncManager.shared.syncStates[document.id.uuidString] ?? .idle
    }

    /// The most recently recognized text from OCR.
    var lastRecognizedText: String = ""

    /// The current PKDrawing — kept in sync with the SketchDocument.
    var currentDrawing: PKDrawing

    /// The document this view model is editing.
    var document: SketchDocument

    // MARK: - Private Properties

    private let notionService = NotionService()

    // MARK: - Whiteboard Bridge

    /// Lazily-created whiteboard state layer. Not used by current canvas interaction;
    /// provided for later tasks that manage objects, z-ordering, and multi-layer rendering.
    private var _whiteboardViewModel: WhiteboardViewModel?
    var whiteboardViewModel: WhiteboardViewModel {
        if _whiteboardViewModel == nil {
            _whiteboardViewModel = WhiteboardViewModel(document: document)
        }
        return _whiteboardViewModel!
    }

    // MARK: - Init

    init(document: SketchDocument) {
        self.document = document
        // Use effectiveDrawingForLegacyCanvas so that when contentVersion == 1,
        // the PKCanvasView renders the freehand layer from the whiteboard document.
        self.currentDrawing = document.effectiveDrawingForLegacyCanvas
    }

    // MARK: - Drawing Changed (Debounce Entry Point)

    /// Called every time `PKCanvasView` reports a drawing change.
    /// Saves locally immediately, then requests a background sync via Manager.
    ///
    /// When `contentVersion == 0` (legacy), persists directly to `document.drawing`.
    /// When `contentVersion == 1` (whiteboard), updates the freehandPencilKit object
    /// inside `document.whiteboard` and encodes it back to JSON.
    func drawingDidChange(_ drawing: PKDrawing) {
        currentDrawing = drawing
        // Mark the local edit time so library sync's last-write-wins check can
        // tell a genuine local edit apart from an older remote one.
        document.lastEditedLocally = Date()

        if document.contentVersion == 0 {
            // Legacy path: persist PKDrawing directly, exactly as before.
            document.drawing = drawing
        } else {
            // Whiteboard path: update the freehandPencilKit object in the whiteboard document.
            // PKCanvasView remains the "freehand layer" — a layered whiteboard renderer arrives in later tasks.
            var wbDoc = document.whiteboard ?? WhiteboardDocument()

            // Find the first .freehandPencilKit object by render order
            let freehandIndex = wbDoc.objects.firstIndex { obj in
                if case .freehandPencilKit = obj.kind { return true }
                return false
            }

            let base64 = drawing.dataRepresentation().base64EncodedString()

            if let idx = freehandIndex {
                // Replace the drawing data in the existing freehand object.
                wbDoc.objects[idx].kind = .freehandPencilKit(drawingDataBase64: base64)
            } else {
                // No freehand object yet — append one at the bottom z-index with default geometry.
                let newObj = WhiteboardObject(
                    kind: .freehandPencilKit(drawingDataBase64: base64),
                    zIndex: WhiteboardZIndex.bottomZIndex(of: wbDoc.objects),
                    x: 0,
                    y: 0,
                    width: 100,
                    height: 100
                )
                wbDoc.objects.append(newObj)
            }

            document.whiteboard = wbDoc
        }

        updateThumbnail(from: drawing)

        // Don't sync if the canvas is empty
        guard !drawing.strokes.isEmpty else { return }

        // Don't sync if not configured
        guard SettingsManager.shared.isConfigured else {
            return
        }

        // Request background sync (debounced 10s)
        NotionSyncManager.shared.requestSync(document: document)
    }

    // MARK: - Force Sync

    /// Immediately syncs the current drawing to Notion, bypassing the debounce timer.
    func forceSyncNow() {
        guard !currentDrawing.strokes.isEmpty else { return }
        guard SettingsManager.shared.isConfigured else { return }

        SyncLogger.log("Force sync triggered")
        NotionSyncManager.shared.forceSync(document: document)
    }
    
    // MARK: - Remote Sync (Title & Properties)
    
    /// Fetches remote title from Notion.
    func fetchRemoteProperties() async {
        guard let pageID = document.notionPageID else { return }
        guard SettingsManager.shared.isConfigured else { return }
        
        do {
            if let (title, _, _) = try await notionService.fetchPageDetails(pageID: pageID) {
                // 1. Sync Title
                if !title.isEmpty && title != document.title {
                    SyncLogger.log("🔄 Title synced from Notion: '\(title)'")
                    document.title = title
                }
            }
        } catch {
            SyncLogger.log("⚠️ Failed to fetch remote properties: \(error.localizedDescription)")
        }
    }

    // MARK: - Sync Pipeline
    
    // Old performSync logic removed (moved to NotionSyncManager)



    // MARK: - Thumbnail Generation

    /// Generates a small preview thumbnail and saves it to the document.
    private func updateThumbnail(from drawing: PKDrawing) {
        guard !drawing.strokes.isEmpty else {
            document.thumbnailData = nil
            return
        }

        let oldBounds = document.drawing.bounds
        let newBounds = drawing.bounds

        if oldBounds == newBounds && document.thumbnailData != nil {
            return
        }

        let bounds = drawing.bounds
        let padding: CGFloat = 10

        let imageRect = CGRect(
            x: bounds.origin.x - padding,
            y: bounds.origin.y - padding,
            width: bounds.width + padding * 2,
            height: bounds.height + padding * 2
        )

        // Render at 1x scale, small size for thumbnail
        let maxDimension: CGFloat = 300
        let scale = min(maxDimension / imageRect.width, maxDimension / imageRect.height, 1.0)
        let thumbnail = drawing.image(from: imageRect, scale: scale)
        document.thumbnailData = thumbnail.pngData()
    }
}
