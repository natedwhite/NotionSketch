import Foundation
import PencilKit
import UIKit
import Observation
import Combine
import Vision
import SwiftData

// MARK: - Notion Sync Manager (Singleton)

@MainActor
@Observable
final class NotionSyncManager {
    static let shared = NotionSyncManager()
    
    /// Public UI state
    var syncStates: [String: SyncState] = [:]
    
    // Internal state for serialization
    private struct DocumentSyncState {
        var isSyncing: Bool = false
        var waitingForSyncToEnd: Bool = false 
        var debounceTask: Task<Void, Never>? // The waiter (can be cancelled freely)
        var syncTask: Task<Void, Never>?     // The worker (protected from debounce cancellation)
    }
    
    private var documentStates: [String: DocumentSyncState] = [:]
    private let notionService = NotionService()
    
    // Cache for relation target DB
    private var cachedTargetDatabaseID: String? = nil
    
    /// Requests a sync for the given document with a debounce delay.
    func requestSync(document: SketchDocument, delay: Duration = AppConstants.Sync.debounceDelay) {
        let id = document.id.uuidString
        var state = documentStates[id] ?? DocumentSyncState()
        
        // 1. Reset any "queued" status — we are starting a new debounce window
        state.waitingForSyncToEnd = false
        
        // 2. Cancel existing debounce timer
        // ALWAYS SAFE now because the actual sync runs in a separate 'syncTask'
        state.debounceTask?.cancel()
        
        // 3. Schedule execution
        state.debounceTask = Task {
            do {
                if delay > .seconds(0) {
                    try await Task.sleep(for: delay)
                }
                await triggerSync(for: document)
            } catch { }
        }
        
        documentStates[id] = state
    }
    
    /// Forces an immediate sync for the document.
    func forceSync(document: SketchDocument) {
        requestSync(document: document, delay: .seconds(0))
    }
    
    /// Called when debounce fires.
    private func triggerSync(for document: SketchDocument) async {
        let id = document.id.uuidString
        guard var state = documentStates[id] else { return }
        
        // If already syncing, mark as queued to run immediately after
        if state.isSyncing {
            state.waitingForSyncToEnd = true
            documentStates[id] = state
            return
        }
        
        // Start separate worker task for the heavy lifting
        // We store it so we can track it, but we don't cancel it from requestSync
        state.syncTask = Task {
            await performExclusively(document: document)
        }
        documentStates[id] = state
    }
    
    /// Runs the sync serialization logic.
    private func performExclusively(document: SketchDocument) async {
        let id = document.id.uuidString
        
        // Mark as syncing
        if var state = documentStates[id] {
            state.isSyncing = true
            // We consume the 'waiting' flag here? 
            // Actually requestSync clears it. 
            // If we are here, we are starting.
            state.waitingForSyncToEnd = false 
            documentStates[id] = state
        }
        
        // Perform the actual heavy lifting
        await performSync(document: document)
        
        // Check if debounce fired while we were busy
        var shouldRestart = false
        if var state = documentStates[id] {
            state.isSyncing = false
            shouldRestart = state.waitingForSyncToEnd
            documentStates[id] = state
        }
        
        // If a trigger happened while we were syncing, run again
        if shouldRestart {
            await performExclusively(document: document)
        }
    }
    
    private func performSync(document: SketchDocument) async {
        let id = document.id.uuidString
        syncStates[id] = .syncing
        SyncLogger.log("🔄 Starting Sync for \(document.title)")
        
        var step = "init"
        
        do {
            // 0. Check for Remote Updates (Page Body)
            if let existingPageID = document.notionPageID {
                step = "checkRemote"
                // Check if different from local (using Page Body)
                if let remoteEncoding = try? await notionService.fetchPageBlocks(pageID: existingPageID),
                   !remoteEncoding.isEmpty {
                    
                    let localEncoding = try? await notionService.encodeDrawing(document.drawing)
                    if let local = localEncoding, local != remoteEncoding {
                        // Conflict / Diff detected.
                        // Currently prioritizing LOCAL PUSH.
                    }
                }
            }

            // 1. Generate Image & Encoding
            step = "imageGeneration"
            let image = drawingToImage(document.drawing)
            let drawingEncoding = try? await notionService.encodeDrawing(document.drawing)
            
            // 2. OCR
            step = "ocr"
            let recognizedText = await recognizeText(in: image)
            
            // 3. Upload Image
            step = "uploadImage"
            let fileUploadID = try await notionService.uploadDrawingImage(image)
            
            // 4. Update/Create Page (Metadata Only)
            let pageID: String
            let appLink = "notionsketch://open?id=\(document.id.uuidString)"
            
            // Note: We no longer pass `drawingEncoding` to these methods as we use Page Body now.
            if let existingPageID = document.notionPageID {
                step = "updatePage"
                try await notionService.updatePageProperties(
                    pageID: existingPageID,
                    title: document.title,
                    ocrText: recognizedText,
                    appLink: appLink,
                    drawingEncoding: nil // CLEAR property if it exists? Or just ignore.
                )
                pageID = existingPageID
                // We no longer clear all page blocks, as we want to preserve user content and the stable container.
                // The updateSketchPreview method handles the image update.
                // We no longer clear the page blocks, as we want to preserve user content and the stable container.
                
            } else {
                step = "createPage"
                pageID = try await notionService.createPageInDatabase(
                    title: document.title,
                    ocrText: recognizedText,
                    appLink: appLink,
                    drawingEncoding: nil
                )
                document.notionPageID = pageID
            }
            
            // 5. Update Synced Image
            step = "updateSyncedImage"
            
            let isFirstSync = (document.syncedBlockID == nil)
            
            let syncedBlockID = try await notionService.updateSyncedImage(
                pageID: pageID,
                syncedBlockID: document.syncedBlockID,
                fileUploadID: fileUploadID,
                recognizedText: recognizedText
            )
            
            // Save synced block ID
            if document.syncedBlockID != syncedBlockID {
                 document.syncedBlockID = syncedBlockID
                 
                 if isFirstSync {
                      try? await notionService.deleteLegacyPreview(pageID: pageID)
                 }
            }
            
            // 6. Update Drawing Data (Page Body Code Block)
            if let encoding = drawingEncoding {
                step = "updateDrawingData"
                try await notionService.updatePageContent(pageID: pageID, drawingString: encoding)
            }
            
            // 7. Sync Connected Pages
            step = "syncRelations"
            await fetchRemoteProperties(for: document)
            
            document.lastSyncedAt = Date()
            syncStates[id] = .success
            scheduleSuccessDismiss(for: id)
            SyncLogger.log("✅ Sync complete for \(document.title)")
            
        } catch {
            let nsError = error as NSError
            if nsError.code != NSURLErrorCancelled {
                SyncLogger.log("❌ Sync Failed: \(error.localizedDescription)")
            }
            // Do not show error state if we are offline or if it's a cancellation
            if !Task.isCancelled {
                // Check if offline
                if NetworkMonitor.shared.isConnected {
                     syncStates[id] = .error("Step: \(step) — \(error.localizedDescription)")
                } else {
                    // Start waiting for reconnection? Or just go to idle.
                    // If we go to .idle, the user sees nothing, which is fine since the "X" is visible.
                    syncStates[id] = .idle
                }
            }
        }
    }
    
    private func scheduleSuccessDismiss(for id: String) {
        Task {
            try? await Task.sleep(for: AppConstants.Sync.successDismissDelay)
            if syncStates[id] == .success {
                syncStates[id] = .idle
            }
        }
    }
    
    // MARK: - Helpers
    
    private func drawingToImage(_ drawing: PKDrawing) -> UIImage {
        let bounds = drawing.bounds
        let padding: CGFloat = AppConstants.Sync.imagePadding
        let imageRect = CGRect(
            x: bounds.origin.x - padding,
            y: bounds.origin.y - padding,
            width: bounds.width + padding * 2,
            height: bounds.height + padding * 2
        )
        return drawing.image(from: imageRect, scale: AppConstants.Sync.imageScale)
    }
    
    private func recognizeText(in image: UIImage) async -> String {
        guard let cgImage = image.cgImage else { return "" }
        
        return await Task.detached(priority: .userInitiated) {
            let request = VNRecognizeTextRequest()
            request.recognitionLevel = .accurate
            request.usesLanguageCorrection = true
            let handler = VNImageRequestHandler(cgImage: cgImage, options: [:])
            
            do {
                try handler.perform([request])
                guard let observations = request.results else { return "" }
                return observations.compactMap { $0.topCandidates(1).first?.string }.joined(separator: " ")
            } catch {
                return ""
            }
        }.value
    }
    
    /// Fetches remote properties and updates the document. 
    private func fetchRemoteProperties(for document: SketchDocument) async {
        guard let pageID = document.notionPageID else { return }
        
        // Ensure target DB known
        if cachedTargetDatabaseID == nil {
            cachedTargetDatabaseID = try? await notionService.fetchConnectedPagesTargetDatabaseID()
        }
        
        guard let (title, _, connectedIDs, _) = try? await notionService.fetchPageDetails(pageID: pageID) else { return }
        
        // 1. Update Title
        if !title.isEmpty && title != document.title {
            document.title = title
        }
        
        // 2. Update Relations
        if Set(document.connectedPageIDs) != Set(connectedIDs) {
            document.connectedPageIDs = connectedIDs
        }
    }
    
    /// Explicitly pulls the latest drawing state from Notion (Page Body).
    func pullFromNotion(document: SketchDocument) async {
         guard let pageID = document.notionPageID else { return }
         
         SyncLogger.log("⬇️ Pulling from Notion: \(document.title)")
         
         do {
             // Fetch Metadata
             if let (title, _, connectedIDs, _) = try await notionService.fetchPageDetails(pageID: pageID) {
                 if !title.isEmpty && title != document.title {
                     document.title = title
                 }
                 if Set(document.connectedPageIDs) != Set(connectedIDs) {
                     document.connectedPageIDs = connectedIDs
                 }
             }
             
             // Fetch Drawing Data (Block)
             if let encoding = try await notionService.fetchPageBlocks(pageID: pageID), !encoding.isEmpty {
                 let newDrawing = try await notionService.decodeDrawing(from: encoding)
                 await MainActor.run {
                     document.drawing = newDrawing
                     document.updateThumbnail()
                 }
                 SyncLogger.log("🎨 Updated drawing from Notion (Body)!")
             } else {
                 SyncLogger.log("ℹ️ No drawing data found in page body.")
             }
         } catch {
             SyncLogger.log("❌ Pull failed: \(error.localizedDescription)")
         }
    }
    
    // MARK: - Library Sync (Deletions & Imports)
    
    /// Synchronizes the entire library with Notion:
    /// 1. Prunes local sketches that were deleted/archived in Notion.
    /// 2. Imports new pages from Notion that don't exist locally.
    /// 3. Updates titles/properties for existing matches.
    func syncLibrary(context: ModelContext) async {
        guard SettingsManager.shared.isConfigured else { return }
        
        SyncLogger.log("🔄 Starting Library Sync...")
        
        do {
            // 0. Fetch local state
            let descriptor = FetchDescriptor<SketchDocument>(sortBy: [SortDescriptor(\.createdAt, order: .reverse)])
            let localSketches = try context.fetch(descriptor)
            
            // 1. Fetch all active page IDs from Notion
            let activePageIDs = try await notionService.fetchActivePageIDs()
            
            // Normalize IDs: strip hyphens, lowercase
            let normalizedActive = Set(activePageIDs.map { $0.replacingOccurrences(of: "-", with: "").lowercased() })
            var localMap = Dictionary(uniqueKeysWithValues: localSketches.compactMap { sketch -> (String, SketchDocument)? in
                guard let id = sketch.notionPageID else { return nil }
                return (id.replacingOccurrences(of: "-", with: "").lowercased(), sketch)
            })
            
            SyncLogger.log("📋 Library Status: \(normalizedActive.count) active remote, \(localMap.count) synced local")
            
            // 2. Process Deletions (Local sketch exists, but remote ID is missing)
            var deletedCount = 0
            for (localID, sketch) in localMap {
                if !normalizedActive.contains(localID) {
                    SyncLogger.log("🗑️ Page \(sketch.notionPageID ?? "") not found active in Notion — removing '\(sketch.title)'")
                    context.delete(sketch)
                    deletedCount += 1
                    localMap.removeValue(forKey: localID) // Remove from map so we don't process it further
                }
            }
            
            // 3. Process Imports (Remote ID exists, but no local sketch)
            var importedCount = 0
            for remoteID in activePageIDs {
                let normalizedRemote = remoteID.replacingOccurrences(of: "-", with: "").lowercased()
                
                if localMap[normalizedRemote] == nil {
                    // This is a new/restored page from Notion!
                    SyncLogger.log("📥 Found new/restored page \(remoteID) — importing...")
                    
                    do {
                        // A. Fetch Details
                        guard let (title, _, connectedIDs, _) = try await notionService.fetchPageDetails(pageID: remoteID) else {
                            SyncLogger.log("⚠️ Failed to fetch details for \(remoteID)")
                            continue
                        }
                        
                        // B. Fetch Drawing Data (Body)
                        guard let drawingEncoded = try await notionService.fetchPageBlocks(pageID: remoteID),
                              !drawingEncoded.isEmpty else {
                            SyncLogger.log("ℹ️ Page \(remoteID) has no drawing data (in body) to import.")
                            continue
                        }
                        
                        // C. Decode & Import
                        let drawing = try await notionService.decodeDrawing(from: drawingEncoded)
                        let drawingData = drawing.dataRepresentation()
                        
                        // Create new document
                        let newSketch = SketchDocument(
                            title: title.isEmpty ? "Imported Sketch" : title,
                            drawingData: drawingData,
                            notionPageID: remoteID
                        )
                        newSketch.connectedPageIDs = connectedIDs
                        newSketch.updateThumbnail() // Generate thumbnail
                        
                        context.insert(newSketch)
                        importedCount += 1
                        SyncLogger.log("✅ Imported '\(newSketch.title)'")
                        
                        // Add a small delay to be nice to the API
                        try await Task.sleep(for: AppConstants.Sync.librarySyncDelay)
                        
                    } catch {
                        SyncLogger.log("❌ Failed to import page \(remoteID): \(error.localizedDescription)")
                    }
                } else {
                    // 4. Update existing? (Optional: Sync Title if changed)
                    // We could do this here lightly.
                    if let existing = localMap[normalizedRemote] {
                         // We won't pull full body here to save bandwidth, just ensure alignment if needed.
                         // For now, let's leave body sync to "Pull" or open.
                    }
                }
            }
            
            if deletedCount > 0 || importedCount > 0 {
                SyncLogger.log("✅ Library Sync Complete: \(deletedCount) deleted, \(importedCount) imported.")
            } else {
                SyncLogger.log("✅ Library Sync Complete: Up to date.")
            }
            
        } catch {
            SyncLogger.log("⚠️ Library Sync Failed: \(error.localizedDescription)")
        }
    }
}
