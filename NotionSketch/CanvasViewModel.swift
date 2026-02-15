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
    
    private var targetDatabaseID: String? = nil
    private let notionService = NotionService()

    // MARK: - Init

    init(document: SketchDocument) {
        self.document = document
        self.currentDrawing = document.drawing
    }

    // MARK: - Drawing Changed (Debounce Entry Point)

    /// Called every time `PKCanvasView` reports a drawing change.
    /// Saves locally immediately, then requests a background sync via Manager.
    func drawingDidChange(_ drawing: PKDrawing) {
        currentDrawing = drawing

        // Persist to SwiftData immediately (local save is cheap)
        document.drawing = drawing
        updateThumbnail(from: drawing)
        
        // Don't sync if the canvas is empty
        guard !drawing.strokes.isEmpty else { return }

        // Don't sync if not configured
        guard SettingsManager.shared.isConfigured else {
            // Error state handled elsewhere or show alert?
            // syncState is computed now. We can't set it easily.
            // NotionSyncManager will error if called.
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
    
    /// Fetches remote properties (Title, Linked Pages) from Notion.
    func fetchRemoteProperties() async {
        guard let pageID = document.notionPageID else { return }
        guard SettingsManager.shared.isConfigured else { return }
        
        // 0. Ensure target database for filtered search is known
        if targetDatabaseID == nil {
            targetDatabaseID = try? await notionService.fetchConnectedPagesTargetDatabaseID()
            if let dbID = targetDatabaseID {
                SyncLogger.log("🎯 Resolved target database for Connected Pages: \(dbID)")
            }
        }
        
        do {
            if let (title, _, connectedIDs, _) = try await notionService.fetchPageDetails(pageID: pageID) {
                // 1. Sync Title
                if !title.isEmpty && title != document.title {
                    SyncLogger.log("🔄 Title synced from Notion: '\(title)'")
                    document.title = title
                }
                
                // 2. Sync Connected Page IDs (Overwrite/Source of Truth)
                // We update local to match remote exactly. This handles additions AND deletions in Notion.
                // Note: Offline additions might be lost if not synced before this runs.
                if Set(document.connectedPageIDs) != Set(connectedIDs) {
                    SyncLogger.log("🔄 Syncing connected pages from Notion (Remote: \(connectedIDs.count), Local: \(document.connectedPageIDs.count))")
                    document.connectedPageIDs = connectedIDs
                    await refreshConnectedPageDetails() // Fetch details for new IDs and prune old
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



    // MARK: - Connected Pages Logic
    
    struct ConnectedPageItem: Identifiable, Hashable {
        let id: String
        let title: String
        let icon: String?
    }
    
    var connectedPages: [ConnectedPageItem] {
        document.connectedPageIDs.map { id in
            let info = document.connectedPageCache[id]
            return ConnectedPageItem(id: id, title: info?.title ?? "Loading...", icon: info?.icon)
        }
    }
    
    /// Searches for pages in Notion to link (optionally filtering by target database).
    func searchPages(query: String) async -> [ConnectedPageItem] {
        guard !query.isEmpty else { return [] }
        
        // Helper to convert results to view models
        func mapResults(_ results: [(id: String, title: String, icon: String?)]) -> [ConnectedPageItem] {
            results
                .filter { $0.id.replacingOccurrences(of: "-", with: "") != document.notionPageID?.replacingOccurrences(of: "-", with: "") } // Exclude self
                .map { ConnectedPageItem(id: $0.id, title: $0.title, icon: $0.icon) }
        }

        // 1. Check for Manual override in Settings
        let manualID = SettingsManager.shared.connectedPagesDatabaseID
        if !manualID.isEmpty {
            targetDatabaseID = manualID
        }

        // 2. Lazy load target DB if not yet cached/configured
        if targetDatabaseID == nil {
             targetDatabaseID = try? await notionService.fetchConnectedPagesTargetDatabaseID()
        }

        // 3. Strict Query
        // We require a target database ID (manual or auto-detected).
        guard let dbID = targetDatabaseID else {
            // If we can't find a DB, we return empty (Strict mode).
            // User can now configure it manually if auto-detection fails.
            SyncLogger.log("⚠️ Cannot search: Target database not resolved. Please configure 'Connected Pages Database' in Settings.")
            return []
        }

        do {
            let results = try await notionService.queryDatabase(databaseID: dbID, query: query)
            return mapResults(results)
        } catch {
            SyncLogger.log("⚠️ Targeted search failed: \(dbID) - \(error.localizedDescription)")
            return []
        }
    }
    
    /// Links a Notion page to this sketch.
    func addConnectedPage(_ item: ConnectedPageItem) {
        guard !document.connectedPageIDs.contains(item.id) else { return }
        
        document.connectedPageIDs.append(item.id)
        // Optimistic update
        document.connectedPageCache[item.id] = ConnectedPageInfo(title: item.title, icon: item.icon)
        
        Task {
            await syncConnectedPages()
        }
    }
    
    /// Unlinks a Notion page from this sketch.
    func removeConnectedPage(id: String) {
        document.connectedPageIDs.removeAll { $0 == id }
        
        Task {
            await syncConnectedPages()
        }
    }
    
    /// Resolves details for all bridged page IDs and cleans up stale cache.
    func refreshConnectedPageDetails() async {
        let ids = document.connectedPageIDs
        
        // 1. Prune stale cache entries
        await MainActor.run {
            let cachedKeys = Set(document.connectedPageCache.keys)
            let activeKeys = Set(ids)
            let staleKeys = cachedKeys.subtracting(activeKeys)
            
            for key in staleKeys {
                 document.connectedPageCache.removeValue(forKey: key)
            }
        }

        guard !ids.isEmpty else { return }
        
        // 2. Fetch details from Notion
        let resolved = await notionService.resolvePageDetails(pageIDs: ids)
        
        await MainActor.run {
            for (id, (title, icon)) in resolved {
                document.connectedPageCache[id] = ConnectedPageInfo(title: title, icon: icon)
            }
        }
    }
    
    /// Syncs the current list of connected page IDs to the Sketch's Notion page.
    private func syncConnectedPages() async {
        guard let pageID = document.notionPageID else {
            // If the sketch isn't in Notion yet, we can't sync relations.
            // They will be synced when the sketch is first created/synced relative to the main pipeline? 
            // NOTE: Currently main pipeline doesn't include relations. 
            // TODO: Ensure createPage/updatePage includes them or we trigger this after main sync.
            return 
        }
        
        do {
            try await notionService.updateConnectedPages(pageID: pageID, targetPageIDs: document.connectedPageIDs)
        } catch {
            SyncLogger.log("⚠️ Failed to sync connected pages: \(error.localizedDescription)")
        }
    }
    // scheduleSuccessDismiss removed (managed by NotionSyncManager)
}
