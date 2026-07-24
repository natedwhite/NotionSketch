import Foundation
import PencilKit
import Observation

@Observable
@MainActor
final class WhiteboardViewModel {

    var whiteboard: WhiteboardDocument

    // MARK: - Computed

    /// Objects sorted by z-index for rendering (bottom to top).
    var objectsSortedForRender: [WhiteboardObject] {
        WhiteboardZIndex.renderSorted(whiteboard.objects)
    }

    // MARK: - Init / Persist

    init(document: SketchDocument) {
        self.whiteboard = document.whiteboard ?? WhiteboardDocument()
    }

    func persist(to document: SketchDocument) {
        document.whiteboard = whiteboard
    }

    // MARK: - Z-Order Operations

    /// Move selected objects one step forward (up) in z-order.
    func bringForward(for selectedIDs: Set<UUID>) {
        guard !selectedIDs.isEmpty else { return }

        let sorted = objectsSortedForRender
        let selectedIndices = sorted.indices.filter { selectedIDs.contains(sorted[$0].id) }
        guard !selectedIndices.isEmpty else { return }

        let minSelectedIndex = selectedIndices.min()!
        guard minSelectedIndex > 0 else { return }

        let above = sorted.indices.filter { $0 < minSelectedIndex && !selectedIDs.contains(sorted[$0].id) }
        guard let targetIndex = above.max() else { return }

        _swapZIndices(betweenSelected: selectedIDs, andTargetIndex: targetIndex, in: sorted)
    }

    /// Move selected objects one step backward (down) in z-order.
    func sendBackward(for selectedIDs: Set<UUID>) {
        guard !selectedIDs.isEmpty else { return }

        let sorted = objectsSortedForRender
        let selectedIndices = sorted.indices.filter { selectedIDs.contains(sorted[$0].id) }
        guard !selectedIndices.isEmpty else { return }

        let maxSelectedIndex = selectedIndices.max()!
        guard maxSelectedIndex < sorted.count - 1 else { return }

        let below = sorted.indices.filter { $0 > maxSelectedIndex && !selectedIDs.contains(sorted[$0].id) }
        guard let targetIndex = below.min() else { return }

        _swapZIndices(betweenSelected: selectedIDs, andTargetIndex: targetIndex, in: sorted)
    }

    /// Move selected objects to the very front (top z-index).
    func bringToFront(for selectedIDs: Set<UUID>) {
        guard !selectedIDs.isEmpty else { return }

        let currentMax = WhiteboardZIndex.topZIndex(of: whiteboard.objects)
        for i in whiteboard.objects.indices {
            if selectedIDs.contains(whiteboard.objects[i].id) {
                whiteboard.objects[i].zIndex = currentMax + 1
            }
        }
    }

    /// Move selected objects to the very back (bottom z-index).
    func sendToBack(for selectedIDs: Set<UUID>) {
        guard !selectedIDs.isEmpty else { return }

        let currentMin = WhiteboardZIndex.bottomZIndex(of: whiteboard.objects)
        for i in whiteboard.objects.indices {
            if selectedIDs.contains(whiteboard.objects[i].id) {
                whiteboard.objects[i].zIndex = currentMin - 1
            }
        }
    }

    // MARK: - Z-Swap Helper

    /// Swap z-indexes between all selected objects and the nearest non-selected neighbor
    /// at `targetIndex` in the render-sorted array.
    private func _swapZIndices(
        betweenSelected selectedIDs: Set<UUID>,
        andTargetIndex targetIndex: Int,
        in sorted: [WhiteboardObject]
    ) {
        let targetZ = sorted[targetIndex].zIndex
        let selectedZs = sorted.enumerated()
            .filter { selectedIDs.contains($0.element.id) }
            .map { $0.element.zIndex }
        let minSelectedZ = selectedZs.min()!

        let targetObjID = sorted[targetIndex].id

        for i in whiteboard.objects.indices {
            let objID = whiteboard.objects[i].id
            if selectedIDs.contains(objID) {
                whiteboard.objects[i].zIndex = targetZ
            } else if objID == targetObjID {
                whiteboard.objects[i].zIndex = minSelectedZ
            }
        }
    }

    // MARK: - Object Insertion

    /// Create or replace the single primary `.freehandPencilKit` object.
    /// - Returns: The `id` of the affected (created or updated) freehand object.
    @discardableResult
    func insertFreehandFromCurrentDrawing(_ drawing: PKDrawing) -> UUID {
        let base64 = drawing.dataRepresentation().base64EncodedString()

        if let existingIndex = whiteboard.objects.firstIndex(where: {
            if case .freehandPencilKit = $0.kind { return true }
            return false
        }) {
            whiteboard.objects[existingIndex].kind = .freehandPencilKit(drawingDataBase64: base64)
            return whiteboard.objects[existingIndex].id
        }

        let newObj = WhiteboardObject(
            kind: .freehandPencilKit(drawingDataBase64: base64),
            zIndex: WhiteboardZIndex.bottomZIndex(of: whiteboard.objects),
            x: 0,
            y: 0,
            width: 100,
            height: 100
        )
        whiteboard.objects.append(newObj)
        return newObj.id
    }

#if DEBUG
    // MARK: - Debug Self-Checks

    /// Validate that all object IDs are unique.
    func validateUniqueIDs() {
        let ids = whiteboard.objects.map(\.id)
        let unique = Set(ids)

        if ids.count != unique.count {
            let duplicates = ids.reduce(into: [UUID: Int]()) { result, id in
                result[id, default: 0] += 1
            }.filter { $0.value > 1 }

            SyncLogger.log(
                "WhiteboardViewModel [ERROR] Duplicate object IDs found: \(duplicates.map { "\($0.key) x\($0.value)" })"
            )
        } else {
            SyncLogger.log("WhiteboardViewModel [OK] All \(ids.count) object IDs are unique.")
        }
    }

    /// Validate that all selected IDs reference existing objects.
    func validateSelectionIDsExist() {
        let objectIDs = Set(whiteboard.objects.map(\.id))
        let orphans = whiteboard.selection.selectedIDs.subtracting(objectIDs)

        if !orphans.isEmpty {
            SyncLogger.log(
                "WhiteboardViewModel [WARNING] Selection contains \(orphans.count) ID(s) not found in objects: \(orphans)"
            )
        } else {
            SyncLogger.log(
                "WhiteboardViewModel [OK] All \(whiteboard.selection.selectedIDs.count) selection ID(s) reference existing objects."
            )
        }
    }

    /// Validate that z-index values have no gaps (informational only; never crashes).
    func validateZIndexNoGaps() {
        guard !whiteboard.objects.isEmpty else {
            SyncLogger.log("WhiteboardViewModel [OK] No objects — z-index gap check skipped.")
            return
        }

        let zs = whiteboard.objects.map(\.zIndex).sorted()
        let minZ = zs.first!
        let maxZ = zs.last!
        let expected = Set(minZ...maxZ)
        let actual = Set(zs)
        let gaps = expected.subtracting(actual)

        if gaps.isEmpty {
            SyncLogger.log(
                "WhiteboardViewModel [OK] Z-index range \(minZ)..\(maxZ) has no gaps."
            )
        } else {
            SyncLogger.log(
                "WhiteboardViewModel [NOTE] Z-index range \(minZ)..\(maxZ) has gaps at: \(gaps.sorted())"
            )
        }
    }
#endif
}
