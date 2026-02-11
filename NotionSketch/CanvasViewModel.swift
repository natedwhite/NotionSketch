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
    var syncState: SyncState = .idle

    /// The most recently recognized text from OCR.
    var lastRecognizedText: String = ""

    /// The current PKDrawing — kept in sync with the SketchDocument.
    var currentDrawing: PKDrawing

    /// The document this view model is editing.
    var document: SketchDocument

    // MARK: - Private Properties
    
    private var targetDatabaseID: String? = nil
    private let notionService = NotionService()
    private var debounceTask: Task<Void, Never>?
    private let debounceDuration: Duration = .seconds(3)
    private var successDismissTask: Task<Void, Never>?

    // MARK: - Init

    init(document: SketchDocument) {
        self.document = document
        self.currentDrawing = document.drawing
    }

    // MARK: - Drawing Changed (Debounce Entry Point)

    /// Called every time `PKCanvasView` reports a drawing change.
    /// Saves locally immediately, then debounces the Notion sync.
    func drawingDidChange(_ drawing: PKDrawing) {
        currentDrawing = drawing

        // Persist to SwiftData immediately (local save is cheap)
        document.drawing = drawing
        updateThumbnail(from: drawing)

        // Cancel any pending sync debounce
        debounceTask?.cancel()

        // Don't sync if the canvas is empty
        guard !drawing.strokes.isEmpty else {
            syncState = .idle
            return
        }

        // Don't sync if not configured
        guard SettingsManager.shared.isConfigured else {
            syncState = .error("Open Settings to add your Notion API token & database")
            return
        }

        debounceTask = Task { [weak self] in
            guard let self else { return }

            do {
                try await Task.sleep(for: self.debounceDuration)
                await self.performSync(drawing: drawing)
            } catch {
                // Task was canceled (user drew another stroke) — do nothing
            }
        }
    }

    // MARK: - Force Sync

    /// Immediately syncs the current drawing to Notion, bypassing the debounce timer.
    func forceSyncNow() {
        debounceTask?.cancel()

        guard !currentDrawing.strokes.isEmpty else {
            syncState = .error("Nothing to sync — canvas is empty")
            SyncLogger.log("Force sync aborted: canvas is empty")
            return
        }

        guard SettingsManager.shared.isConfigured else {
            syncState = .error("Open Settings to add your Notion API token & database")
            SyncLogger.log("Force sync aborted: not configured")
            return
        }

        SyncLogger.log("Force sync triggered")
        Task {
            await performSync(drawing: currentDrawing)
        }
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
            if let (title, _, connectedIDs) = try await notionService.fetchPageDetails(pageID: pageID) {
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
    
    /// Full sync pipeline: OCR → Upload Image → Create/Update Notion Page.
    private func performSync(drawing: PKDrawing) async {
        syncState = .syncing
        var step = "init"
        SyncLogger.log("--- Sync started ---")

        do {
            // 1. Convert drawing to image
            step = "convertImage"
            let image = drawingToImage(drawing)
            SyncLogger.log("✅ Step 1: Drawing converted to image (\(image.size))")

            // 2. Run OCR
            step = "ocr"
            let recognizedText = await recognizeText(in: image)
            lastRecognizedText = recognizedText
            SyncLogger.log("✅ Step 2: OCR complete — \"\(recognizedText.prefix(80))\"")

            // 3. Upload image via Notion File Upload API
            step = "uploadImage"
            SyncLogger.log("Step 3: Uploading image...")
            let fileUploadID = try await notionService.uploadDrawingImage(image)
            SyncLogger.log("✅ Step 3: Image uploaded — ID: \(fileUploadID)")

            // 4. Ensure we have a Notion page
            let pageID: String
            let appLink = "notionsketch://open?id=\(document.id.uuidString)"

            if let existingPageID = document.notionPageID {
                step = "updatePage"
                SyncLogger.log("Step 4: Updating page properties & clearing blocks...")
                
                // Update properties (Title, OCR, Link)
                try await notionService.updatePageProperties(
                    pageID: existingPageID,
                    title: document.title,
                    ocrText: recognizedText,
                    appLink: appLink
                )
                
                pageID = existingPageID
                try await notionService.clearPageBlocks(pageID: pageID)
                SyncLogger.log("✅ Step 4: Properties updated & blocks cleared")
            } else {
                step = "createPage"
                SyncLogger.log("Step 4: Creating new page in database")
                pageID = try await notionService.createPageInDatabase(
                    title: document.title,
                    ocrText: recognizedText,
                    appLink: appLink
                )
                document.notionPageID = pageID
                SyncLogger.log("✅ Step 4: Page created — ID: \(pageID)")
            }

            // 5. Append blocks to the page
            step = "appendBlocks"
            SyncLogger.log("Step 5: Appending blocks...")
            try await notionService.appendToNotionPage(
                pageID: pageID,
                fileUploadID: fileUploadID,
                recognizedText: recognizedText
            )
            SyncLogger.log("✅ Step 5: Blocks appended")

            // 6. Success!
            // Sync connected pages property from Notion to ensure we are up to date
            await fetchRemoteProperties()
            
            document.lastSyncedAt = Date()
            syncState = .success
            scheduleSuccessDismiss()
            SyncLogger.log("✅ Sync complete!")

        } catch {
            SyncLogger.log("❌ FAILED at step: \(step)")
            SyncLogger.log("❌ Error type: \(type(of: error))")
            SyncLogger.log("❌ Error: \(error)")
            SyncLogger.log("❌ Localized: \(error.localizedDescription)")
            if !Task.isCancelled {
                syncState = .error("Step: \(step) — \(error.localizedDescription)")
            }
        }
    }

    // MARK: - Drawing → UIImage

    private func drawingToImage(_ drawing: PKDrawing) -> UIImage {
        let bounds = drawing.bounds
        let padding: CGFloat = 20

        let imageRect = CGRect(
            x: bounds.origin.x - padding,
            y: bounds.origin.y - padding,
            width: bounds.width + padding * 2,
            height: bounds.height + padding * 2
        )

        return drawing.image(from: imageRect, scale: 2.0)
    }

    // MARK: - Thumbnail Generation

    /// Generates a small preview thumbnail and saves it to the document.
    private func updateThumbnail(from drawing: PKDrawing) {
        guard !drawing.strokes.isEmpty else {
            document.thumbnailData = nil
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

    // MARK: - OCR via Vision Framework

    private func recognizeText(in image: UIImage) async -> String {
        guard let cgImage = image.cgImage else { return "" }

        return await withCheckedContinuation { continuation in
            let request = VNRecognizeTextRequest { request, error in
                guard error == nil,
                      let observations = request.results as? [VNRecognizedTextObservation]
                else {
                    continuation.resume(returning: "")
                    return
                }

                let recognizedStrings = observations.compactMap { observation in
                    observation.topCandidates(1).first?.string
                }

                let combined = recognizedStrings.joined(separator: " ")
                continuation.resume(returning: combined)
            }

            request.recognitionLevel = .accurate
            request.usesLanguageCorrection = true

            let handler = VNImageRequestHandler(cgImage: cgImage, options: [:])

            do {
                try handler.perform([request])
            } catch {
                continuation.resume(returning: "")
            }
        }
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
        
        // If we know the target database for the relation, filter by it!
        if let dbID = targetDatabaseID {
            do {
                let results = try await notionService.queryDatabase(databaseID: dbID, query: query)
                // Filter out existing connected pages? App will do this, or here?
                // For now, raw results.
                return results.map { ConnectedPageItem(id: $0.id, title: $0.title, icon: $0.icon) }
            } catch {
                SyncLogger.log("⚠️ Targeted search failed: \(dbID) - \(error.localizedDescription) — Returning empty results (strict filter)")
                return []
            }
        }
        
        do {
            let results = try await notionService.searchNotionPages(query: query)
            return results.map { ConnectedPageItem(id: $0.id, title: $0.title, icon: $0.icon) }
        } catch {
            SyncLogger.log("⚠️ Search failed: \(error.localizedDescription)")
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
    // MARK: - Auto-dismiss Success State

    private func scheduleSuccessDismiss() {
        successDismissTask?.cancel()
        successDismissTask = Task {
            do {
                try await Task.sleep(for: .seconds(4))
                if syncState == .success {
                    syncState = .idle
                }
            } catch {
                // Canceled — no-op
            }
        }
    }
}
